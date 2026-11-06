//! Go standard library behaviour the migrated kernels must keep.
//!
//! The crates that live behind Go code need the same four things: `strings.ToLower` /
//! `strings.TrimSpace` folding, `regexp` syntax translation, the domain suffix helpers built on top
//! of them and `dns.StringToType`. Keeping one copy here means the Android policy kernel and the
//! desktop filter kernel cannot drift apart on the details that Go pinned (context-free case
//! mapping, ASCII shorthands, one-trailing-dot trimming, the record-type mnemonics).
//!
//! * [`text`] - `strings`/`normalizePolicyDomain` equivalents.
//! * [`regex`] - Go `regexp` -> Rust `regex` translation and rule-pattern compilation.
//! * [`dns_type`] - `dns.StringToType`, the table rule modifiers are resolved against.

pub mod dns_type;
pub mod regex;
pub mod text;
