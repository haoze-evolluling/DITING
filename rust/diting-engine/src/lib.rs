//! The Rust Android tunnel engine.
//!
//! This crate replaces the Go engine that used to arrive as `tunnel-*.aar`. Stage 1 covered the
//! standalone DNS server (the mode `DitingDnsServerService` starts) end to end; stage 2 completed the
//! resolver: plain UDP/TCP, DoH, DoT, DoQ, the bootstrap dialer, the upstream trust store and the
//! four scheduler strategies. Stage 3a added the TUN data plane: the descriptor adapter, the
//! transparent `smoltcp` stack, DNS over the TUN, the flow gate, traffic accounting and the JNI
//! entry points. Later stages added the non-DNS relays (direct/SOCKS5/HTTP CONNECT), the MITM
//! termination and the Kotlin switches for express and normal mode, so all three modes now run on
//! this engine.
//!
//! # What is new here, and what is not
//!
//! Every decision the Go engine made by calling a Rust kernel through the C ABI is still made by
//! the same kernel, only now through its Rust API:
//!
//! | Go (old) | Kernel (direct) |
//! |---|---|
//! | `policy_native.go` | [`diting_policy_core::Snapshot`] |
//! | `dns_core_native.go` / `dns_reply_native.go` | [`diting_dns_core`] |
//! | `dns_cache_native*.go` | [`diting_dns_cache_core::Cache`] |
//! | `log_aggregator.go` | [`diting_telemetry_core::LogAggregator`] |
//! | `dns_config.go` | [`diting_config_core::dns_config::normalize`] |
//! | `resolver_*.go`'s statistics | [`diting_resolver_core::ProviderStats`] |
//! | `resolver_strategy.go` (order, budgets, hedge, grace, race log) | [`diting_resolver_core::Schedule`] |
//! | `bootstrap_resolver.go`'s scoring and host cache | [`diting_bootstrap_core::BootstrapKernel`] |
//! | `resolver_*.go`'s constants, framing and DoH status table | [`diting_upstream_core`] |
//! | `gate.go`'s admission order and `engine_connection_log.go`'s dedupe | [`diting_gate_core`] / [`diting_connlog_core`] |
//! | `uid_cache.go`'s TTL caches, `traffic_tracker.go`'s counters | [`diting_telemetry_core`] |
//!
//! What is new is the part Go owned: the sockets, the server loop, the provider attempt order, the
//! JSON the UI reads and the JNI facade.
//!
//! # Layout
//!
//! * [`config`] — the `ApplyDNSConfig` JSON model, its normalization and the cache policy mapping.
//! * [`engine`] — the engine state: cache, policy snapshot, rewrite table, counters, logs.
//! * [`dns`] — one query through the pipeline: DDR / local asset / rewrite / policy / cache /
//!   upstream, in exactly the order `serveDNS` used.
//! * [`resolver`] — the provider list, the four upstream transports (PLAIN UDP/TCP, DoH, DoT, DoQ),
//!   the bootstrap dialer, the platform trust store and the scheduler driver.
//! * [`standalone`] — the IPv4/IPv6 UDP and TCP server.
//! * [`netstack`] — the transparent TCP/IP stack (`smoltcp`, any destination address and port).
//! * [`tunnel`] — the TUN session: reader/stack/writer threads, the bounded queues, DNS over the
//!   TUN, the flow gate and the traffic counters.
//! * [`mitm`] — stage 4b: the root CA and leaf minting, the TLS termination, the HTTP/1.1 relay,
//!   the cosmetic injection and the local asset server.
//! * [`protect`] — `VpnService.protect`, consulted by every dial before it connects.
//! * [`attribution`] — 5-tuple → UID → package, with the kernels' TTL caches.
//! * [`logs`] — the batch log flusher and the JNI callback thread.
//! * [`stats`] — the `getStats` / `getDNSCacheStats` / `getDNSCacheEntries` JSON documents.
//! * [`jni`] — the entry points and the handle registry (`nativeNew`/`nativeFree`).

pub mod attribution;
pub mod cache;
pub mod config;
pub mod dns;
pub mod engine;
pub mod error;
pub mod jni;
pub mod logs;
pub mod mitm;
pub mod netstack;
pub mod outbound;
pub mod panic_log;
pub mod pause;
pub mod policy;
pub mod protect;
pub mod resolver;
pub mod standalone;
pub mod stage3;
pub mod stats;
pub mod tunnel;

pub use engine::Engine;
pub use error::EngineError;
