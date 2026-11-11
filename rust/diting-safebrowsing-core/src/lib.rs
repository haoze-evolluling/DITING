//! Safe Browsing / parental-control hash-prefix kernel for the desktop service
//! (`desktop/service/internal/core`).
//!
//! This crate owns the reputation module's decision logic: host canonicalization, the SHA-256 of
//! the domain and of every parent domain up to eTLD+1, the query name built from the 2-byte
//! prefixes, the parsing of the 64-hex TXT answers, and the prefix-keyed LRU cache with its TTL.
//! The Go side keeps what cannot move without a callback: the resolver call, the fail-open policy,
//! the timeout and the counters that feed the UI.
//!
//! Layout:
//! * [`hash`] — host normalization/validation, the digest set, the query name and TXT parsing.
//! * [`cache`] — the prefix-keyed LRU: lookup / store / expiry / eviction.
//! * [`engine`] — one state per process: the two checkers (Safe Browsing and parental control).
//! * [`payload`] — the binary layouts shared with `safebrowsing_native*.go`.
//! * [`ffi`] — the C ABI [`ffi::ABI_VERSION`] the Go loader validates.
//!
//! Time is injected: `plan` and `apply` take `now_ms`, so the kernel has no clock of its own and
//! cache expiry is pinned by the tests instead of by sleeps.
//!
//! The library is required: a missing library fails `NewSafeBrowsingEngine`, which fails service
//! startup. There is no second implementation in Go — a silent one would quietly turn the
//! protection off while the UI still said it was on.

pub mod cache;
pub mod engine;
pub mod ffi;
pub mod hash;
pub mod payload;

pub use engine::{
    Engine, Plan, PARENTAL_CONTROL_SUFFIX, SAFE_BROWSING_SUFFIX, SERVICE_PARENTAL_CONTROL,
    SERVICE_SAFE_BROWSING,
};
pub use ffi::ABI_VERSION;
pub use hash::{
    build_question_name, hostname_to_hashes, normalize_check_host, parse_txt_hashes, HashPrefix,
    HostnameHash, HASH_HEX_SIZE, HASH_PREFIX_LEN, HASH_SIZE, HASH_SUB_DOMAIN_NUM,
};
