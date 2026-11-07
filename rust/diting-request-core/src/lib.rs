//! The request-path filter of the Android tunnel engine.
//!
//! `SetRequestRules` installs URL prefix rules (block / allow) and `requestFilterDecision` consults
//! them for every plaintext HTTP request the MITM relay sees. Both halves moved here:
//!
//! * [`rules`] — the rule table: `strings.ToLower(strings.TrimSpace(pattern))`, the `block` /
//!   `allow` kind whitelist and the mandatory `http://` / `https://` prefix. Invalid rules are
//!   dropped silently, exactly as before.
//! * [`match`] — the decision: host normalization (lower-case, trim, strip the scheme's default
//!   port), the `path == ""` default, the `scheme://host path` URL build, the longest-prefix walk
//!   with allow winning ties, and the host the domain-rule fallback should be asked about.
//!
//! Go keeps `encoding/json` (the rule payload shape), `net/http` (reading the request and writing the
//! 403), the domain-rule fallback itself and the log lines. The kernel holds one immutable rule set
//! per handle, so a settings change builds a new handle and drops the old one; a missing library
//! means no request rule ever matches and the fallback keeps working.

pub mod ffi;
pub mod match_rule;
pub mod payload;
pub mod rules;
