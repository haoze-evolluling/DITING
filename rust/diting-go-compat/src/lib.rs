//! Go standard library behaviour the migrated kernels must keep.
//!
//! Both crates that live behind Go code need the same three things: `strings.ToLower` /
//! `strings.TrimSpace` folding, `regexp` syntax translation and the domain suffix helpers built on
//! top of them. Keeping one copy here means the Android policy kernel and the desktop rule index
//! cannot drift apart on the details that Go pinned (context-free case mapping, ASCII shorthands,
//! one-trailing-dot trimming).
//!
//! * [`text`] - `strings`/`normalizePolicyDomain` equivalents.
//! * [`regex`] - Go `regexp` -> Rust `regex` translation and rule-pattern compilation.

pub mod regex;
pub mod text;
