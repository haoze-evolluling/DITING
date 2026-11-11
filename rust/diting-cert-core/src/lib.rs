//! The MITM certificate authority of the Android tunnel engine.
//!
//! This crate is the crypto half of `android/engine/mitm_cert_manager.go` after migration:
//!
//! * [`ca`] - the root CA lifecycle (generate a P-256 self-signed CA, load and validate one from
//!   disk, mint per-host leaf certificates, export both as PEM) and the shared leaf key;
//! * [`ev`] - the extended-validation policy OID table behind
//!   `mitm_trust.go`'s "do not inspect bank-grade certificates" decision;
//! * [`pem`] - a tolerant PEM reader (`pem.Decode` semantics: leading text allowed, first block
//!   wins) and the encoder used for every artifact;
//! * [`ffi`] - the C ABI `android/engine/cert_native.go` loads with `dlopen`.
//!
//! Go keeps what needs Go types: the minted-certificate LRU (its values are `*tls.Certificate`),
//! the per-host single-flight wait group, the file names and the read/write of `ca.crt` / `ca.key`,
//! and `tls.X509KeyPair` on the bytes the kernel returns. The kernel never reads a clock: every
//! entry point takes `now_unix` seconds and the caller decides what "now" is.
//!
//! A missing kernel is a hard failure: `NewCertManager` reports it, so MITM does not start. The
//! tunnel itself keeps running (without interception), which is the same shape as the other
//! MITM-related kernels.

pub mod ca;
pub mod ev;
pub mod ffi;
pub mod pem;
