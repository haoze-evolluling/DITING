//! Stage 3 kernels linked directly into `libditing_engine.so` (K1).
//!
//! The desktop service already ships three kernels the Android engine used to be missing:
//!
//! * [`safebrowsing`] — Safe Browsing / parental-control hash-prefix reputation (U10);
//! * [`dns64`] — RFC 6052/6147 AAAA synthesis for IPv6-only networks (N8);
//! * [`ratelimit`] — per-client token-bucket limiting for server mode (N9).
//!
//! They are ordinary Rust dependencies (no `dlopen`, no C ABI payload codec), exactly like the other
//! engine-side kernels. This module forces the link and exposes the one accessor the pipeline and
//! the server-mode client table share, so there is a single place that names them.

pub use diting_dns64_core as dns64;
pub use diting_ratelimit_core as ratelimit;
pub use diting_safebrowsing_core as safebrowsing;

/// The three kernels and their payload-layout versions, for diagnostics and a startup check.
pub const LINKED_KERNELS: [(&str, u32); 3] = [
    ("safebrowsing", diting_safebrowsing_core::ABI_VERSION),
    ("dns64", diting_dns64_core::ABI_VERSION),
    ("ratelimit", diting_ratelimit_core::ABI_VERSION),
];

/// Builds the safe-browsing kernel with the configured cache size / TTL.
///
/// The engine creates one and stores it when the feature is enabled; a disabled feature never calls
/// this, so the cache is never allocated for users who did not turn it on.
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
            .plan(diting_safebrowsing_core::SERVICE_SAFE_BROWSING, "example.com", 0)
            .expect("a domain has a plan");
        // Whether the cache was warm or not, the plan is a valid Safe Browsing decision.
        assert!(plan.empty || !plan.question.is_empty() || plan.found);
    }
}
