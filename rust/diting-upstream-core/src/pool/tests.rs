use super::*;

#[test]
fn entries_are_reused_newest_first() {
    let pool = DotPool::new();
    assert_eq!(pool.acquire("dns:853", 0), None);
    assert!(pool.release("dns:853", 1, 0));
    assert!(pool.release("dns:853", 2, 0));
    assert_eq!(pool.len("dns:853"), 2);

    assert_eq!(pool.acquire("dns:853", 100), Some(Acquired::Idle(2)));
    assert_eq!(pool.acquire("dns:853", 100), Some(Acquired::Idle(1)));
    assert_eq!(pool.acquire("dns:853", 100), None);
}

#[test]
fn an_entry_past_the_idle_window_is_expired() {
    let pool = DotPool::new();
    assert!(pool.release("dns:853", 7, 1000));
    assert_eq!(pool.acquire("dns:853", 15_999), Some(Acquired::Idle(7)));
    assert!(pool.release("dns:853", 7, 1000));
    // 15 s after the last write it is still usable; one millisecond later it is not.
    assert_eq!(pool.acquire("dns:853", 16_000), Some(Acquired::Idle(7)));
    assert!(pool.release("dns:853", 7, 1000));
    assert_eq!(pool.acquire("dns:853", 16_001), Some(Acquired::Expired(7)));
    assert_eq!(pool.len("dns:853"), 0);
}

#[test]
fn only_four_connections_per_target_are_kept() {
    let pool = DotPool::new();
    for id in 1..=TUNING.dot_max_idle_conns_per_host as u64 {
        assert!(pool.release("dns:853", id, 0), "id {id}");
    }
    assert_eq!(pool.len("dns:853"), 4);
    assert!(!pool.release("dns:853", 5, 0));
    assert_eq!(pool.len("dns:853"), 4);
    // A different target has its own budget.
    assert!(pool.release("other:853", 6, 0));
}

#[test]
fn close_all_returns_every_id_and_empties_the_pool() {
    let pool = DotPool::new();
    pool.release("a:853", 1, 0);
    pool.release("a:853", 2, 0);
    pool.release("b:853", 3, 0);
    let mut ids = pool.close_all();
    ids.sort_unstable();
    assert_eq!(ids, vec![1, 2, 3]);
    assert!(pool.is_empty());
    assert_eq!(pool.acquire("a:853", 0), None);
    assert_eq!(pool.close_all(), Vec::<u64>::new());
}

#[test]
fn a_clock_that_goes_backwards_does_not_expire_an_entry() {
    let pool = DotPool::new();
    assert!(pool.release("dns:853", 9, 10_000));
    assert_eq!(pool.acquire("dns:853", 5_000), Some(Acquired::Idle(9)));
}
