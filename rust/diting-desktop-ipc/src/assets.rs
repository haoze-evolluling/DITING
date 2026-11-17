//! Embedded single-page application assets.
//!
//! `build.rs` turns `desktop/service/frontend/dist` into a compile-time table. When that directory
//! is absent (a backend-only checkout) the table is empty and [`PLACEHOLDER`] is served instead.

include!(concat!(env!("OUT_DIR"), "/dist_assets.rs"));

/// Minimal landing page served when the frontend bundle was not built.
pub const PLACEHOLDER: &[u8] = b"<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>\xe8\xb0\x9b\xe5\x90\xac DNS</title></head><body style=\"font-family:sans-serif;text-align:center;padding:50px;\"><h2>\xe8\xb0\x9b\xe5\x90\xac (DITING) \xe6\x9c\x8d\xe5\x8a\xa1\xe8\xbf\x90\xe8\xa1\x8c\xe4\xb8\xad</h2><p>\xe6\x9c\xaa\xe5\x8a\xa0\xe8\xbd\xbd\xe5\x89\x8d\xe7\xab\xaf\xe9\x9d\x99\xe6\x80\x81\xe8\xb5\x84\xe6\xba\x90\xe5\x8c\x85</p></body></html>";

/// Looks an asset up by its URL path (leading slash optional).
pub fn lookup(path: &str) -> Option<(&'static [u8], String)> {
    let key = normalize(path);
    let key = if key.is_empty() {
        "index.html"
    } else {
        key.as_str()
    };
    ASSETS
        .iter()
        .find(|(name, _)| *name == key)
        .map(|(_, data)| (*data, mime_for(key)))
}

pub fn has_assets() -> bool {
    HAS_ASSETS
}

/// Normalizes a URL path the way `path.Clean` would for the asset table.
pub fn normalize(path: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    for part in path.split('/') {
        match part {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            other => parts.push(other),
        }
    }
    parts.join("/")
}

/// Content type for a file name. Matches the explicit Go map for the extensions that matter.
pub fn mime_for(name: &str) -> String {
    let lower = name.to_ascii_lowercase();
    let extension = lower.rsplit_once('.').map(|(_, ext)| ext).unwrap_or("");
    match extension {
        "html" | "htm" => "text/html; charset=utf-8".to_string(),
        "js" | "mjs" => "text/javascript; charset=utf-8".to_string(),
        "css" => "text/css; charset=utf-8".to_string(),
        "json" => "application/json".to_string(),
        "svg" => "image/svg+xml".to_string(),
        "ico" => "image/x-icon".to_string(),
        "png" => "image/png".to_string(),
        "jpg" | "jpeg" => "image/jpeg".to_string(),
        "webp" => "image/webp".to_string(),
        "woff2" => "font/woff2".to_string(),
        "woff" => "font/woff".to_string(),
        "ttf" => "font/ttf".to_string(),
        "map" => "application/json".to_string(),
        "txt" => "text/plain; charset=utf-8".to_string(),
        _ => mime_guess::from_path(name)
            .first_raw()
            .unwrap_or("application/octet-stream")
            .to_string(),
    }
}
