//! The cosmetic ad-blocking kernel behind the Android tunnel engine: the injected `<link>`, the
//! stylesheet it points at, and the local asset server that serves it.
//!
//! The engine injects one `<link rel="stylesheet">` into every intercepted HTML page so the local
//! asset server can serve the selectors scoped to that page's hostname. Four things have to agree
//! for that to work on a stream it does not control:
//!
//! * [`inject`] — the streaming scanner. It accepts whatever `Read` hands it, keeps at most one
//!   partial `<head` marker in `carry`, parks the bytes that did not fit into the caller's buffer
//!   in `pending`, and stops scanning after [`inject::SCAN_LIMIT`] bytes.
//! * [`host`] — `normalizeCosmeticHost` plus the `<link>` tag itself: lowercase, drop the port only
//!   when `net.SplitHostPort` accepted the authority, strip one trailing dot, and escape the query
//!   value the way `url.QueryEscape` does.
//! * [`rules`] — the pushed rule set, compiled once per `SetCosmeticRules` instead of re-decoded on
//!   every stylesheet request: the host suffix walk, the hide/exception merge and the byte-ordered
//!   stylesheet, including the two sentinel bodies for an empty and an undecodable payload.
//! * [`local`] — the embedded asset server's answer: route selection (`/cosmetic.css`, `/health`,
//!   404), status, content type, the five fixed headers (`Vary` and `private` caching on the
//!   stylesheet alone) and the body. [`local::is_asset_host`] is the host match the flow handler
//!   uses to route a connection here at all.
//!
//! `ShouldInjectHTML` and `requestAcceptsHTML` stay in Go: each is one `strings.Contains` on a header
//! the relay already has, and a kernel call would only add an error path to a per-response predicate.
//!
//! Go keeps `encoding/json` (the rule payload is Kotlin's), the `net/http` objects, the body reader,
//! the log lines and the zlib plumbing. See `rust/README.md` for the boundary, including the two
//! places where the old Go code was wrong and this kernel is not.

pub mod ffi;
pub mod host;
pub mod inject;
pub mod local;
pub mod payload;
pub mod rules;

pub use host::{link_tag, normalize_host, query_escape};
pub use inject::{Injector, Outcome, Upstream, HEAD_TAG, SCAN_LIMIT};
pub use local::{is_asset_host, respond, Response};
pub use rules::{host_suffixes, DomainRules, RuleSet, Rules};
