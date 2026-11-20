pub use diting_dns64_core as dns64;
pub use diting_ratelimit_core as ratelimit;
pub use diting_safebrowsing_core as safebrowsing;

pub const LINKED_KERNELS: [(&str, u32); 3] = [
    ("safebrowsing", diting_safebrowsing_core::ABI_VERSION),
    ("dns64", diting_dns64_core::ABI_VERSION),
    ("ratelimit", diting_ratelimit_core::ABI_VERSION),
];

pub fn safebrowsing_engine(cache_size: i64, cache_ttl_ms: i64) -> diting_safebrowsing_core::Engine {
    diting_safebrowsing_core::Engine::new(cache_size, cache_ttl_ms)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kernels_are_linked_and_versioned() {
        for (name, version) in LINKED_KERNELS {
            assert!(version >= 1, "{name} abi version");
        }
    }

    #[test]
    fn safebrowsing_kernel_is_reachable() {
        let engine = safebrowsing_engine(16, 60_000);
        let plan = engine
            .plan(
                diting_safebrowsing_core::SERVICE_SAFE_BROWSING,
                "example.com",
                0,
            )
            .expect("a domain has a plan");
        assert!(plan.empty || !plan.question.is_empty() || plan.found);
    }
}
