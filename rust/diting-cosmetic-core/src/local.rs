//! The embedded local asset server: routing, the response headers and the stylesheet body.
//!
//! `ServeLocalAsset` is the only HTTP server the engine hosts itself. It never dials anything, so
//! everything about a response except the `net/http` plumbing is a pure decision: which route the
//! path selects, the status, the content type, the five fixed headers (plus `Vary` on the stylesheet)
//! and the body. That decision lives here; Go keeps `http.Request` / `http.Response`, the body reader
//! and `http.StatusText`.
//!
//! The stylesheet is per page host and must not be cached under another site's name, which is why it
//! alone carries `Vary: X-DITING-Host` and `Cache-Control: private, max-age=300`.

use crate::host::normalize_host;
use crate::rules::RuleSet;

/// The hostname the engine answers itself; `LocalAssetHost` in Go.
pub const ASSET_HOST: &str = "local.pwhs.app";

/// The stylesheet path; `crate::host::ASSET_PATH`.
const CSS_PATH: &str = "/cosmetic.css";
const HEALTH_PATH: &str = "/health";

const CSS_CONTENT_TYPE: &str = "text/css; charset=utf-8";
const JSON_CONTENT_TYPE: &str = "application/json";
const TEXT_CONTENT_TYPE: &str = "text/plain";

/// One response, in the order `buildTextResponse` filled the header map in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub status: u16,
    pub content_type: &'static str,
    /// `(name, value)` in a fixed order; Go copies them into `http.Header`.
    pub headers: Vec<(&'static str, String)>,
    pub body: String,
}

/// `IsLocalAssetHost`: lowercase, trim, drop everything after the last `:`, compare.
///
/// This is *not* `net.SplitHostPort`: the old helper cut at the last colon whatever came before it,
/// so `[::1]:443` becomes `[::1]` and a bare `::1` becomes `:`. `local.pwhs.app:8443` matches.
pub fn is_asset_host(host: &str) -> bool {
    let mut lowered =
        diting_go_compat::text::go_lower(diting_go_compat::text::go_trim_space(host)).into_owned();
    if let Some(index) = lowered.rfind(':') {
        lowered.truncate(index);
    }
    lowered == ASSET_HOST
}

/// `ServeLocalAsset`: the response for one request.
///
/// `path` is `req.URL.Path` (already decoded by `net/url`), `host_query` is `?h=` as the request
/// carried it (normalization happens here), and `payload_bytes` is the size of the raw rule payload
/// the `/health` route reports.
pub fn respond(path: &str, host_query: &str, rules: &RuleSet, payload_bytes: u64) -> Response {
    match path {
        CSS_PATH => {
            let body = rules.render(&normalize_host(host_query));
            let mut response = text_response(200, CSS_CONTENT_TYPE, body);
            // The stylesheet depends on the hostname in the query string, so it must not be reused
            // for another site through a shared cache.
            response.set_header("Cache-Control", "private, max-age=300");
            response.headers.push(("Vary", "X-DITING-Host".to_string()));
            response
        }
        HEALTH_PATH => text_response(
            200,
            JSON_CONTENT_TYPE,
            format!(r#"{{"status":"ok","css_bytes":{payload_bytes}}}"#),
        ),
        _ => text_response(404, TEXT_CONTENT_TYPE, "Not Found".to_string()),
    }
}

impl Response {
    fn set_header(&mut self, name: &str, value: &str) {
        if let Some(entry) = self.headers.iter_mut().find(|(key, _)| *key == name) {
            entry.1 = value.to_string();
        }
    }
}

/// `buildTextResponse`: the five headers every local response carries, with the body sized.
fn text_response(status: u16, content_type: &'static str, body: String) -> Response {
    Response {
        status,
        content_type,
        headers: vec![
            ("Content-Type", content_type.to_string()),
            ("Content-Length", body.len().to_string()),
            ("Cache-Control", "public, max-age=300".to_string()),
            ("Access-Control-Allow-Origin", "*".to_string()),
            ("X-DITING", "local-asset-server".to_string()),
        ],
        body,
    }
}

#[cfg(test)]
mod tests;
