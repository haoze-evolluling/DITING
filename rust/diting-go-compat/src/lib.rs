//! Go standard library behaviour the migrated kernels must keep.
//!
//! The crates that live behind Go code need the same handful of things: `strings.ToLower` /
//! `strings.ToUpper` / `strings.TrimSpace` folding, `regexp` syntax translation, the domain suffix
//! helpers built on top of them, `dns.StringToType` and `net.IP` semantics. Keeping one copy here
//! means the Android kernels and the desktop kernels (rule index, rule text, rewrite records) cannot
//! drift apart on the details that Go pinned (context-free case mapping, ASCII shorthands,
//! one-trailing-dot trimming, the record-type mnemonics, dotted/mapped/RFC 5952 address text).
//!
//! * [`text`] - `strings`/`normalizePolicyDomain` equivalents.
//! * [`regex`] - Go `regexp` -> Rust `regex` translation and rule-pattern compilation.
//! * [`dns_type`] - `dns.StringToType`, the table rule modifiers are resolved against.
//! * [`ip`] - `net.IP` string form, `To4`, `IsLoopback` and zero equality over raw bytes.
//! * [`netaddr`] - `net.ParseIP`, `SplitHostPort`, `JoinHostPort` and `IP.String` over text.

pub mod dns_type;
pub mod ip;
pub mod netaddr;
pub mod regex;
pub mod text;
