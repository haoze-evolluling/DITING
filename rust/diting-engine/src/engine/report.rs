use super::Engine;

impl Engine {
    pub fn stats_json(&self) -> String {
        crate::stats::engine_stats_json(self)
    }

    pub fn cache_stats_json(&self) -> String {
        crate::cache::stats_json(self.cache.stats())
    }

    pub fn cache_entries_json(&self, limit: i64) -> String {
        if limit <= 0 {
            return "[]".to_string();
        }
        let entries = self.cache.snapshot(limit.min(u32::MAX as i64) as u32);
        crate::cache::entries_json(&entries)
    }
}
