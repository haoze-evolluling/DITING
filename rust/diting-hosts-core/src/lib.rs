//! Local hosts-file kernel for the desktop service (`desktop/service/internal/core`).
//!
//! This crate owns the local authority module: parsing hosts text into the IPv4 / IPv6 / reverse
//! maps, the lookups that answer from them, and the `.in-addr.arpa` / `.ip6.arpa` reverse-name
//! parsing that both the hosts resolver and the rewrite engine used to share.
//!
//! The Go side keeps what needs `dns.RR` or the filesystem layout: the platform hosts path, the
//! `dns.A` / `dns.AAAA` / `dns.PTR` records built from the addresses this kernel returns, the TTL,
//! and the config fields `UpdateConfig` swaps. File reading lives here because the maps are built
//! from files; the Go side passes a source list (paths and, for `LoadReader`, inline text).
//!
//! Layout:
//! * [`ip`] — `net.ParseIP` with the `To4` collapse the old parser relied on.
//! * [`arpa`] — `ParseIPFromArpa`: the reverse names back to an address.
//! * [`hosts`] — the parser and the table (lookup / has-domain / PTR / reverse).
//! * [`payload`] — the binary layouts shared with `hosts_native*.go`.
//! * [`ffi`] — the C ABI [`ffi::ABI_VERSION`] the Go loader validates.
//!
//! The library is required: a missing library fails `NewHostsResolver`, which fails service
//! startup. There is no second parser in Go — a silent one would drift.

pub mod arpa;
pub mod ffi;
pub mod hosts;
pub mod ip;
pub mod payload;

pub use arpa::parse_arpa;
pub use ffi::ABI_VERSION;
pub use hosts::{parse_text, HostsTable, Source, MAX_LINE_BYTES};
pub use ip::{parse_hosts_address, parse_ip, Addr};
