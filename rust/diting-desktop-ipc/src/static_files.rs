//! SPA asset serving with the Go handler's MIME and cache behaviour.

use hyper::header::HeaderValue;
use hyper::http::StatusCode;

use crate::assets;
use crate::handlers::{json_response, Resp};
use crate::response::ApiResponse;

fn html(body: Vec<u8>, status: StatusCode) -> Resp {
    let mut response =
        hyper::Response::new(http_body_util::Full::new(hyper::body::Bytes::from(body)));
    *response.status_mut() = status;
    response.headers_mut().insert(
        hyper::header::CONTENT_TYPE,
        HeaderValue::from_static("text/html; charset=utf-8"),
    );
    response.headers_mut().insert(
        hyper::header::CACHE_CONTROL,
        HeaderValue::from_static("no-cache, no-store, must-revalidate"),
    );
    response
}

fn placeholder() -> Resp {
    html(assets::PLACEHOLDER.to_vec(), StatusCode::OK)
}

/// Serves a static path, falling back to `index.html` for client-side routes.
pub fn serve(path: &str) -> Resp {
    if path.starts_with("/api/") {
        return json_response(
            StatusCode::NOT_FOUND,
            &ApiResponse::<serde_json::Value>::error("api endpoint not found"),
        );
    }
    if !assets::has_assets() {
        return placeholder();
    }

    let key = assets::normalize(path);
    let key = if key.is_empty() {
        "index.html".to_string()
    } else {
        key
    };
    if let Some((data, content_type)) = assets::lookup(&key) {
        let mut response = hyper::Response::new(http_body_util::Full::new(
            hyper::body::Bytes::copy_from_slice(data),
        ));
        *response.status_mut() = StatusCode::OK;
        let headers = response.headers_mut();
        if let Ok(value) = HeaderValue::from_str(&content_type) {
            headers.insert(hyper::header::CONTENT_TYPE, value);
        }
        if key.starts_with("assets/") {
            headers.insert(
                hyper::header::CACHE_CONTROL,
                HeaderValue::from_static("public, max-age=31536000, immutable"),
            );
        } else if key == "index.html" {
            headers.insert(
                hyper::header::CACHE_CONTROL,
                HeaderValue::from_static("no-cache, no-store, must-revalidate"),
            );
        }
        return response;
    }

    match assets::lookup("index.html") {
        Some((data, _)) => html(data.to_vec(), StatusCode::OK),
        None => placeholder(),
    }
}
