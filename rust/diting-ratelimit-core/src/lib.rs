//! Client rate-limiting kernel for the desktop service (`desktop/service/internal/core`).
//!
//! This crate owns the token bucket that `internal/core/rate_limiter.go` used to keep in Go:
//! configuration normalisation, exemption parsing (`net.ParseCIDR` / `net.ParseIP` acceptance),
//! per-client masking (the IPv4 / IPv6 prefix aggregation), the buckets themselves, the capacity
//! eviction and the idle sweep.
//!
//! The Go side keeps what is plumbing rather than policy: the janitor goroutine, the clock (every
//! call carries `now_ns`), `net.IP` byte conversion, `IsEnabled` for the middleware's fast path, and
//! the JSON config shape the IPC layer persists.
//!
//! Layout:
//! * [`ip`] — `net.IP` as this module observed it: 4 or 16 bytes with the `To4` collapse.
//! * [`cidr`] — `net.ParseCIDR` acceptance plus `IPNet.Contains`, including the v4-mapped corner
//!   cases (`::ffff:10.0.0.0/120` behaves like `10.0.0.0/24`, `/96` like `/0`).
//! * [`limiter`] — the configuration, the buckets and the allow decision.
//! * [`payload`] — the binary layouts shared with `ratelimit_native*.go`.
//! * [`ffi`] — the C ABI [`ffi::ABI_VERSION`] the Go loader validates.
//!
//! The kernel is required: a missing library fails `NewRateLimiter`, which fails service startup.
//! There is no second limiter in Go — a silent one would drift.

pub mod cidr;
pub mod ffi;
pub mod ip;
pub mod limiter;
pub mod payload;

pub use cidr::Cidr;
pub use ffi::ABI_VERSION;
pub use ip::Addr;
pub use limiter::{
    Config, Info, Normalized, RateLimiter, DEFAULT_BURST, DEFAULT_IPV4_PREFIX, DEFAULT_IPV6_PREFIX,
    DEFAULT_MAX_BUCKETS, DEFAULT_RATE, IDLE_AFTER_NS,
};
