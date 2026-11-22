use crate::host::normalize_host;
use crate::rules::RuleSet;

pub const ASSET_HOST: &str = "local.pwhs.app";

const CSS_PATH: &str = "/cosmetic.css";
const HEALTH_PATH: &str = "/health";

const CSS_CONTENT_TYPE: &str = "text/css; charset=utf-8";
const JSON_CONTENT_TYPE: &str = "application/json";
const TEXT_CONTENT_TYPE: &str = "text/plain";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Response {
    pub status: u16,
    pub content_type: &'static str,
    pub headers: Vec<(&'static str, String)>,
    pub body: String,
}

pub fn is_asset_host(host: &str) -> bool {
    let mut lowered =
        diting_go_compat::text::go_lower(diting_go_compat::text::go_trim_space(host)).into_owned();
    if let Some(index) = lowered.rfind(':') {
        lowered.truncate(index);
    }
    lowered == ASSET_HOST
}

pub fn respond(path: &str, host_query: &str, rules: &RuleSet, payload_bytes: u64) -> Response {
    match path {
        CSS_PATH => {
            let body = rules.render(&normalize_host(host_query));
            let mut response = text_response(200, CSS_CONTENT_TYPE, body);
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
