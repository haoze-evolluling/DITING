//! Rust core for the Android app's network diagnostics tools.
//!
//! The Kotlin probes (`PingProbe`, `TraceProbe`, `DnsServerProbe`, `DnsLookupProbe`,
//! `DnsLatencyTester`, `NetHost`) keep every socket, process, timer and `ConnectivityManager`
//! read; what moves here is the part that reads bytes and text:
//!
//! * [`host`] - `NetHost.sanitize` and the "is this a literal IP" gate.
//! * [`dns`] - the hand-built A/AAAA query, the "did the resolver answer" check, the custom
//!   server's answer walk (over [`diting_dns_wire`], the reader the DNS kernels already use) and
//!   the DoH endpoint rule.
//! * [`ping`] - `ping` output parsing (replies, loss, per-sequence gaps, the min/avg/max/mdev
//!   block) and the sample arithmetic the latency tester shares.
//! * [`trace`] - one `ping -t <ttl>` run's hop classification.
//! * [`api`] - the request/answer payload layouts, so every codec is testable without a JVM.
//! * [`jni_bridge`] - the entry points `com.haoze.diting.net.ProbeNative` declares.
//!
//! There is no Kotlin implementation left to fall back to: a missing library or a payload from a
//! different layout version fails the probe instead of running a second parser.

pub mod api;
pub mod dns;
pub mod host;
pub mod jni_bridge;
pub mod payload;
pub mod ping;
pub mod trace;

pub use api::{
    build_dns_query, dns_response_succeeded, doh_endpoint, is_ip_literal, latency_stats,
    parse_dns_server_reply, ping_summary, sanitize_host, trace_hop, trace_response_line,
};
pub use dns::{build_query, format_ipv6, parse_server_reply, Answer, QueryType, Reply};
pub use host::sanitize;
pub use ping::{latency_stats as sample_stats, parse_summary, LatencyStats, Summary};
pub use trace::{parse_hop, Hop};
