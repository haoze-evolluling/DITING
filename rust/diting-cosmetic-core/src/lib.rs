//! The cosmetic ad-blocking injection kernel behind the Android tunnel engine.
//!
//! The engine injects one `<link rel="stylesheet">` into every intercepted HTML page so the local
//! asset server can serve the selectors scoped to that page's hostname. Three things have to agree
//! for that to work on a stream it does not control:
//!
//! * [`inject`] - the streaming scanner. It accepts whatever `Read` hands it, keeps at most one
//!   partial `<head` marker in `carry`, parks the bytes that did not fit into the caller's buffer
//!   in `pending`, and stops scanning after [`inject::SCAN_LIMIT`] bytes.
//! * [`host`] - `normalizeCosmeticHost` plus the `<link>` tag itself: lowercase, drop the port only
//!   when `net.SplitHostPort` accepted the authority, strip one trailing dot, and escape the query
//!   value the way `url.QueryEscape` does.
//!
//! `ShouldInjectHTML` stays in Go: it is `strings.Contains(strings.ToLower(ct), "text/html")`, one
//! line that needs no state, and a kernel call would only add an error path to a predicate the
//! relay asks once per response.
//!
//! Go keeps the rule payload (`SetCosmeticRules`), the log line, the response headers and the zlib
//! plumbing. See `rust/README.md` for the boundary, including the two places where the old Go code
//! was wrong and this kernel is not.

pub mod ffi;
pub mod host;
pub mod inject;
pub mod payload;

pub use host::{link_tag, normalize_host, query_escape};
pub use inject::{Injector, Outcome, Upstream, HEAD_TAG, SCAN_LIMIT};
