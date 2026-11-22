use std::cell::UnsafeCell;
use std::mem::MaybeUninit;
use std::sync::atomic::{AtomicUsize, Ordering};

#[repr(align(64))]
struct CachePadded<T>(T);

struct Slot<T> {
    sequence: AtomicUsize,
    value: UnsafeCell<MaybeUninit<T>>,
}

/// 零依赖的无锁有界环形队列（Dmitry Vyukov MPMC/MPSC 变体）。
///
/// 热路径出入队完全无锁、无堆分配；当调用方传入非 2 的幂容量时，
/// 底层按 `next_power_of_two()` 对齐并使用 `reserved` 严格维持逻辑上限。
pub(crate) struct BoundedRing<T> {
    slots: Box<[Slot<T>]>,
    mask: usize,
    capacity: usize,
    enqueue_pos: CachePadded<AtomicUsize>,
    dequeue_pos: CachePadded<AtomicUsize>,
    reserved: CachePadded<AtomicUsize>,
}

unsafe impl<T: Send> Send for BoundedRing<T> {}
unsafe impl<T: Send> Sync for BoundedRing<T> {}

impl<T> BoundedRing<T> {
    pub(crate) fn new(capacity: usize) -> Self {
        if capacity == 0 {
            return Self {
                slots: Box::new([]),
                mask: 0,
                capacity: 0,
                enqueue_pos: CachePadded(AtomicUsize::new(0)),
                dequeue_pos: CachePadded(AtomicUsize::new(0)),
                reserved: CachePadded(AtomicUsize::new(0)),
            };
        }
        // Vyukov 环形队列用 `pos + 1` 标识可读、`pos + ring_cap` 标识可写，
        // 两者必须严格区分，因此底层槽位数至少为 2（capacity == 1 时由 `reserved` 限流）。
        let ring_cap = capacity.max(2).next_power_of_two();
        let slots: Vec<Slot<T>> = (0..ring_cap)
            .map(|index| Slot {
                sequence: AtomicUsize::new(index),
                value: UnsafeCell::new(MaybeUninit::uninit()),
            })
            .collect();
        Self {
            slots: slots.into_boxed_slice(),
            mask: ring_cap - 1,
            capacity,
            enqueue_pos: CachePadded(AtomicUsize::new(0)),
            dequeue_pos: CachePadded(AtomicUsize::new(0)),
            reserved: CachePadded(AtomicUsize::new(0)),
        }
    }

    pub(crate) fn try_push(&self, value: T) -> Result<(), T> {
        if self.capacity == 0 {
            return Err(value);
        }
        let exact_cap = self.capacity < self.slots.len();
        if exact_cap {
            let mut cur = self.reserved.0.load(Ordering::Acquire);
            loop {
                if cur >= self.capacity {
                    return Err(value);
                }
                match self.reserved.0.compare_exchange_weak(
                    cur,
                    cur + 1,
                    Ordering::Acquire,
                    Ordering::Acquire,
                ) {
                    Ok(_) => break,
                    Err(next) => cur = next,
                }
            }
        }

        let mut pos = self.enqueue_pos.0.load(Ordering::Relaxed);
        loop {
            let slot = &self.slots[pos & self.mask];
            let seq = slot.sequence.load(Ordering::Acquire);
            let diff = seq.wrapping_sub(pos) as isize;
            if diff == 0 {
                match self.enqueue_pos.0.compare_exchange_weak(
                    pos,
                    pos.wrapping_add(1),
                    Ordering::Relaxed,
                    Ordering::Relaxed,
                ) {
                    Ok(_) => {
                        // SAFETY: 我们独占了 `pos` 对应的槽位，且 `seq == pos` 保证了它当前未初始化。
                        unsafe { (*slot.value.get()).write(value) };
                        slot.sequence.store(pos.wrapping_add(1), Ordering::Release);
                        return Ok(());
                    }
                    Err(next) => pos = next,
                }
            } else if diff < 0 {
                if exact_cap {
                    self.reserved.0.fetch_sub(1, Ordering::Release);
                }
                return Err(value);
            } else {
                pos = self.enqueue_pos.0.load(Ordering::Relaxed);
            }
        }
    }

    pub(crate) fn try_pop(&self) -> Option<T> {
        if self.capacity == 0 {
            return None;
        }
        let exact_cap = self.capacity < self.slots.len();
        let mut pos = self.dequeue_pos.0.load(Ordering::Relaxed);
        loop {
            let slot = &self.slots[pos & self.mask];
            let seq = slot.sequence.load(Ordering::Acquire);
            let diff = seq.wrapping_sub(pos.wrapping_add(1)) as isize;
            if diff == 0 {
                match self.dequeue_pos.0.compare_exchange_weak(
                    pos,
                    pos.wrapping_add(1),
                    Ordering::Relaxed,
                    Ordering::Relaxed,
                ) {
                    Ok(_) => {
                        // SAFETY: `seq == pos + 1` 且 Acquire 读取与生产者的 Release 同步，值已初始化。
                        let value = unsafe { (*slot.value.get()).assume_init_read() };
                        slot.sequence
                            .store(pos.wrapping_add(self.mask + 1), Ordering::Release);
                        if exact_cap {
                            self.reserved.0.fetch_sub(1, Ordering::Release);
                        }
                        return Some(value);
                    }
                    Err(next) => pos = next,
                }
            } else if diff < 0 {
                return None;
            } else {
                pos = self.dequeue_pos.0.load(Ordering::Relaxed);
            }
        }
    }

    pub(crate) fn len(&self) -> usize {
        let tail = self.enqueue_pos.0.load(Ordering::Acquire);
        let head = self.dequeue_pos.0.load(Ordering::Acquire);
        (tail.wrapping_sub(head) as isize).max(0) as usize
    }

    pub(crate) fn is_empty(&self) -> bool {
        self.len() == 0
    }
}

impl<T> Drop for BoundedRing<T> {
    fn drop(&mut self) {
        while self.try_pop().is_some() {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn non_power_of_two_capacity_enforces_exact_bound() {
        let ring = BoundedRing::new(3);
        assert!(ring.try_push(1).is_ok());
        assert!(ring.try_push(2).is_ok());
        assert!(ring.try_push(3).is_ok());
        assert_eq!(ring.try_push(4), Err(4));
        assert_eq!(ring.len(), 3);
        assert_eq!(ring.try_pop(), Some(1));
        assert!(ring.try_push(4).is_ok());
        assert_eq!(ring.try_pop(), Some(2));
        assert_eq!(ring.try_pop(), Some(3));
        assert_eq!(ring.try_pop(), Some(4));
        assert_eq!(ring.try_pop(), None);
        assert!(ring.is_empty());
    }

    #[test]
    fn mpsc_concurrent_stress_preserves_all_items() {
        let ring = Arc::new(BoundedRing::<usize>::new(256));
        let producers = 4usize;
        let per_producer = 5_000usize;
        let mut handles = Vec::new();
        for tid in 0..producers {
            let r = Arc::clone(&ring);
            handles.push(std::thread::spawn(move || {
                for i in 0..per_producer {
                    let value = tid * per_producer + i;
                    while r.try_push(value).is_err() {
                        std::thread::yield_now();
                    }
                }
            }));
        }

        let total = producers * per_producer;
        let mut seen = vec![false; total];
        let mut popped = 0usize;
        while popped < total {
            if let Some(value) = ring.try_pop() {
                assert!(!seen[value], "duplicate value {value}");
                seen[value] = true;
                popped += 1;
            } else {
                std::thread::yield_now();
            }
        }
        for handle in handles {
            handle.join().unwrap();
        }
        assert!(ring.is_empty());
    }
}
