//! Fixed-capacity overwrite ring for recent query records.
//!
//! Port of the former Go service's `internal/querylog/ring.go`: once full, appends overwrite the oldest
//! entry, logical order is always oldest → newest, and searches walk backwards (newest first).

use std::sync::RwLock;

use super::types::{Record, SearchQuery, DEFAULT_MAX_ENTRIES};

struct RingInner {
    buf: Vec<Record>,
    start: usize,
    size: usize,
    max_size: usize,
    total: u64,
}

impl RingInner {
    fn at(&self, index: usize) -> &Record {
        &self.buf[(self.start + index) % self.max_size]
    }
}

/// Thread-safe overwrite ring buffer.
pub(crate) struct Ring {
    inner: RwLock<RingInner>,
}

impl Ring {
    /// Create a ring with `max_size` slots (`<= 0` falls back to the default capacity).
    pub(crate) fn new(max_size: i32) -> Self {
        let max_size = if max_size <= 0 {
            DEFAULT_MAX_ENTRIES
        } else {
            max_size
        } as usize;
        Self {
            inner: RwLock::new(RingInner {
                buf: vec![Record::default(); max_size],
                start: 0,
                size: 0,
                max_size,
                total: 0,
            }),
        }
    }

    /// Append one record, overwriting the oldest entry when full.
    pub(crate) fn append(&self, record: Record) {
        let mut inner = self.inner.write().unwrap_or_else(|e| e.into_inner());
        let max_size = inner.max_size;
        if inner.size < max_size {
            let slot = (inner.start + inner.size) % max_size;
            inner.buf[slot] = record;
            inner.size += 1;
        } else {
            let oldest = inner.start;
            inner.buf[oldest] = record;
            inner.start = (oldest + 1) % max_size;
        }
        inner.total += 1;
    }

    /// Current number of retained records.
    #[allow(dead_code)]
    pub(crate) fn len(&self) -> usize {
        self.inner.read().unwrap_or_else(|e| e.into_inner()).size
    }

    /// Whether the ring holds no records.
    #[allow(dead_code)]
    pub(crate) fn is_empty(&self) -> bool {
        self.len() == 0
    }

    /// Cumulative number of records ever appended.
    #[allow(dead_code)]
    pub(crate) fn total(&self) -> u64 {
        self.inner.read().unwrap_or_else(|e| e.into_inner()).total
    }

    /// Resize, keeping the newest `min(current, max_size)` records (`<= 0` is ignored).
    pub(crate) fn resize(&self, max_size: i32) {
        if max_size <= 0 {
            return;
        }
        let max_size = max_size as usize;
        let mut inner = self.inner.write().unwrap_or_else(|e| e.into_inner());
        if max_size == inner.max_size {
            return;
        }
        let keep = inner.size.min(max_size);
        let mut buf = vec![Record::default(); max_size];
        for (index, slot) in buf.iter_mut().enumerate().take(keep) {
            *slot = inner.at(inner.size - keep + index).clone();
        }
        inner.buf = buf;
        inner.start = 0;
        inner.size = keep;
        inner.max_size = max_size;
    }

    /// Drop every in-memory record but preserve the configured capacity.
    pub(crate) fn clear(&self) {
        let mut inner = self.inner.write().unwrap_or_else(|e| e.into_inner());
        inner.buf = vec![Record::default(); inner.max_size];
        inner.start = 0;
        inner.size = 0;
    }

    /// Search and apply `offset`/`limit`. Returns newest-first matches plus the full match count.
    #[allow(dead_code)]
    pub(crate) fn search(&self, query: &SearchQuery) -> (Vec<Record>, usize) {
        let (mut all, total) = self.search_all(query);
        if query.offset > 0 {
            let offset = query.offset as usize;
            if offset >= all.len() {
                return (Vec::new(), total);
            }
            all.drain(0..offset);
        }
        if query.limit > 0 && all.len() as i64 > query.limit {
            all.truncate(query.limit as usize);
        }
        (all, total)
    }

    /// Return every match newest-first, without pagination.
    ///
    /// Backwards iteration makes recent hits cheap and allows an early break once records fall
    /// below the `start_ms` lower bound.
    pub(crate) fn search_all(&self, query: &SearchQuery) -> (Vec<Record>, usize) {
        let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
        if inner.size == 0 {
            return (Vec::new(), 0);
        }
        let mut matched = Vec::with_capacity(inner.size.min(64));
        let mut total = 0usize;
        for index in (0..inner.size).rev() {
            let record = inner.at(index);
            if query.start_ms > 0 && record.timestamp < query.start_ms {
                break;
            }
            if !query.matches(record) {
                continue;
            }
            total += 1;
            matched.push(record.clone());
        }
        (matched, total)
    }

    /// Timestamp of the oldest retained record, or `0` when empty.
    pub(crate) fn oldest_timestamp(&self) -> i64 {
        let inner = self.inner.read().unwrap_or_else(|e| e.into_inner());
        if inner.size == 0 {
            0
        } else {
            inner.at(0).timestamp
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    fn record(timestamp: i64, domain: &str) -> Record {
        Record {
            timestamp,
            domain: domain.into(),
            status: super::super::types::STATUS_ALLOWED.into(),
            ..Record::default()
        }
    }

    #[test]
    fn append_and_newest_first_order() {
        let ring = Ring::new(3);
        for i in 1..=3 {
            ring.append(record(i, &format!("d{i}.com")));
        }
        assert_eq!(ring.len(), 3);
        let (got, total) = ring.search(&SearchQuery {
            limit: 10,
            ..SearchQuery::default()
        });
        assert_eq!(total, 3);
        assert_eq!(
            got.iter().map(|r| r.timestamp).collect::<Vec<_>>(),
            vec![3, 2, 1]
        );
    }

    #[test]
    fn overwrite_keeps_newest() {
        let ring = Ring::new(2);
        for i in 1..=4 {
            ring.append(record(i, ""));
        }
        let (got, total) = ring.search(&SearchQuery {
            limit: 10,
            ..SearchQuery::default()
        });
        assert_eq!(total, 2);
        assert_eq!(got[0].timestamp, 4);
        assert_eq!(got[1].timestamp, 3);
        assert_eq!(ring.total(), 4);
    }

    #[test]
    fn resize_keeps_newest() {
        let ring = Ring::new(5);
        for i in 1..=5 {
            ring.append(record(i, ""));
        }
        ring.resize(2);
        let (got, total) = ring.search(&SearchQuery {
            limit: 10,
            ..SearchQuery::default()
        });
        assert_eq!(total, 2);
        assert_eq!(got[0].timestamp, 5);
        assert_eq!(got[1].timestamp, 4);
    }

    #[test]
    fn search_offset_and_limit() {
        let ring = Ring::new(10);
        for i in 1..=6 {
            ring.append(record(i, ""));
        }
        let (got, total) = ring.search(&SearchQuery {
            limit: 2,
            offset: 1,
            ..SearchQuery::default()
        });
        assert_eq!(total, 6);
        assert_eq!(
            got.iter().map(|r| r.timestamp).collect::<Vec<_>>(),
            vec![5, 4]
        );
    }

    #[test]
    fn search_early_break_on_start_ms() {
        let ring = Ring::new(10);
        for i in 1..=6 {
            ring.append(record(i * 1000, ""));
        }
        let (got, total) = ring.search(&SearchQuery {
            start_ms: 4000,
            limit: 10,
            ..SearchQuery::default()
        });
        assert_eq!(total, 3);
        assert_eq!(
            got.iter().map(|r| r.timestamp).collect::<Vec<_>>(),
            vec![6000, 5000, 4000]
        );
    }

    #[test]
    fn clear_and_oldest_timestamp() {
        let ring = Ring::new(4);
        ring.append(record(10, ""));
        ring.append(record(20, ""));
        assert_eq!(ring.oldest_timestamp(), 10);
        ring.clear();
        assert!(ring.is_empty());
        assert_eq!(ring.oldest_timestamp(), 0);
    }

    #[test]
    fn concurrent_append_fills_ring() {
        let ring = Arc::new(Ring::new(1024));
        let mut handles = Vec::new();
        for base in 0..8 {
            let ring = Arc::clone(&ring);
            handles.push(std::thread::spawn(move || {
                for i in 0..200 {
                    ring.append(record(base * 1000 + i, ""));
                }
            }));
        }
        for handle in handles {
            handle.join().expect("join");
        }
        assert_eq!(ring.len(), 1024);
    }
}
