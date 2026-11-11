//! `DnsCacheMirror`'s pure half: how much of the engine's cache is projected, how often, and the
//! `dns_cache` row shape.
//!
//! The engine handle, the JSON decode, the timer and the `DELETE` + `INSERT` transaction stay in
//! Kotlin; the caps, the cadence and the two constant columns (`ttlOffsets`, `response`) live here,
//! because those are the parts a reader of `dns_cache` depends on.

/// Rows requested from `Engine.getDNSCacheEntries` (the hottest ones).
pub const MAX_ROWS: i64 = 200;
/// The first projection waits for the tunnel handshake to settle.
pub const INITIAL_DELAY_MS: i64 = 5_000;
/// Two consecutive frames of the Flutter cache view are 10 s apart.
pub const INTERVAL_MS: i64 = 10_000;

/// The wire bytes are never read back from this projection, so the column stays empty.
pub const EMPTY_TTL_OFFSETS: &str = "";

/// One entry as the engine's JSON reported it.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Entry {
    pub key: String,
    pub query_name: String,
    pub query_type: i32,
    pub query_class: i32,
    pub created_at: i64,
    pub expires_at: i64,
    pub last_hit_at: i64,
    pub hit_count: i64,
    pub original_ttl_seconds: i64,
    pub response_size: i32,
}

/// One `dns_cache` row: the entry plus the two columns the projection fills with constants.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub entry: Entry,
    pub ttl_offsets: &'static str,
    pub response: Vec<u8>,
}

/// `DnsCacheMirror.toValues`: the projection is a straight copy with two NOT NULL columns pinned.
pub fn project(entry: Entry) -> Row {
    Row {
        entry,
        ttl_offsets: EMPTY_TTL_OFFSETS,
        response: Vec::new(),
    }
}

/// The three numbers the timer and the snapshot request need.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Layout {
    pub max_rows: i64,
    pub initial_delay_ms: i64,
    pub interval_ms: i64,
}

pub fn layout() -> Layout {
    Layout {
        max_rows: MAX_ROWS,
        initial_delay_ms: INITIAL_DELAY_MS,
        interval_ms: INTERVAL_MS,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry() -> Entry {
        Entry {
            key: "10|example.com|1".into(),
            query_name: "example.com".into(),
            query_type: 1,
            query_class: 1,
            created_at: 1_000,
            expires_at: 301_000,
            last_hit_at: 2_000,
            hit_count: 7,
            original_ttl_seconds: 300,
            response_size: 45,
        }
    }

    #[test]
    fn the_projection_pins_the_two_constant_columns() {
        let row = project(entry());
        assert_eq!(row.entry, entry());
        assert_eq!(row.ttl_offsets, "");
        assert!(row.response.is_empty());
    }

    #[test]
    fn the_layout_is_the_hot_two_hundred_rows_every_ten_seconds() {
        assert_eq!(
            layout(),
            Layout {
                max_rows: 200,
                initial_delay_ms: 5_000,
                interval_ms: 10_000,
            }
        );
    }
}
