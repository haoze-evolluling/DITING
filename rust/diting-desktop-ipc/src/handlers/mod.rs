#![allow(clippy::result_large_err)]

pub mod auth;
pub mod backup;
pub mod cache;
pub mod clients;
pub mod diagnostics;
pub mod encrypted;
pub mod filter;
pub mod lan;
pub mod openwrt;
pub mod querylog;
pub mod rewrite;
pub mod safesearch;
pub mod security;
pub mod status;
pub mod upstream;
pub mod web;

use std::collections::HashMap;
use std::net::SocketAddr;

use http_body_util::Full;
use hyper::body::Bytes;
use hyper::header::{HeaderMap, HeaderName};
use hyper::http::{Method, StatusCode};
use hyper::{Response, Uri};
use serde::de::DeserializeOwned;
use serde::Serialize;

use diting_desktop_app::controller::ControllerError;

use crate::response::ApiResponse;
use crate::server::Server;

pub type Resp = Response<Full<Bytes>>;

pub struct Ctx<'a> {
    pub method: &'a Method,
    pub query: HashMap<String, String>,
    pub headers: &'a HeaderMap,
    pub remote: SocketAddr,
    pub body: &'a [u8],
}

impl<'a> Ctx<'a> {
    pub fn new(
        method: &'a Method,
        uri: &Uri,
        headers: &'a HeaderMap,
        remote: SocketAddr,
        body: &'a [u8],
    ) -> Self {
        Self {
            method,
            query: parse_query(uri.query().unwrap_or("")),
            headers,
            remote,
            body,
        }
    }

    pub fn is(&self, method: Method) -> bool {
        *self.method == method
    }

    pub fn query_get(&self, key: &str) -> Option<&str> {
        self.query.get(key).map(String::as_str)
    }

    pub fn header(&self, name: &str) -> Option<&str> {
        HeaderName::from_bytes(name.as_bytes())
            .ok()
            .and_then(|name| self.headers.get(name))
            .and_then(|value| value.to_str().ok())
    }

    pub fn json<T: DeserializeOwned>(&self) -> Result<T, Resp> {
        serde_json::from_slice(self.body)
            .map_err(|error| bad_request(format!("解析请求 JSON 失败: {error}")))
    }

    pub fn json_or_default<T: DeserializeOwned + Default>(&self) -> Result<T, Resp> {
        if self.body.iter().all(|byte| byte.is_ascii_whitespace()) {
            Ok(T::default())
        } else {
            self.json()
        }
    }

    pub fn require_method(&self, allowed: &[Method], message: &str) -> Result<(), Resp> {
        if allowed.iter().any(|method| method == self.method) {
            Ok(())
        } else {
            Err(method_not_allowed(message))
        }
    }
}

pub fn parse_query(query: &str) -> HashMap<String, String> {
    let mut out = HashMap::new();
    for pair in query.split('&') {
        if pair.is_empty() {
            continue;
        }
        let (key, value) = pair.split_once('=').unwrap_or((pair, ""));
        out.insert(percent_decode(key), percent_decode(value));
    }
    out
}

fn percent_decode(value: &str) -> String {
    let bytes = value.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut index = 0;
    while index < bytes.len() {
        match bytes[index] {
            b'+' => {
                out.push(b' ');
                index += 1;
            }
            b'%' if index + 2 < bytes.len() => {
                let hex = &value[index + 1..index + 3];
                if let Ok(byte) = u8::from_str_radix(hex, 16) {
                    out.push(byte);
                    index += 3;
                } else {
                    out.push(bytes[index]);
                    index += 1;
                }
            }
            byte => {
                out.push(byte);
                index += 1;
            }
        }
    }
    String::from_utf8_lossy(&out).into_owned()
}

pub fn json_response<T: Serialize>(status: StatusCode, payload: &ApiResponse<T>) -> Resp {
    let body = serde_json::to_vec(payload).unwrap_or_else(|_| b"{\"success\":false}".to_vec());
    let mut response = Response::new(Full::new(Bytes::from(body)));
    *response.status_mut() = status;
    response.headers_mut().insert(
        hyper::header::CONTENT_TYPE,
        hyper::header::HeaderValue::from_static("application/json; charset=utf-8"),
    );
    response
}

pub fn ok<T: Serialize>(data: T) -> Resp {
    json_response(StatusCode::OK, &ApiResponse::ok(data))
}

pub fn ok_message(message: &str) -> Resp {
    json_response(
        StatusCode::OK,
        &ApiResponse::<serde_json::Value>::message(message),
    )
}

pub fn ok_data_message<T: Serialize>(data: T, message: &str) -> Resp {
    json_response(StatusCode::OK, &ApiResponse::ok_message(data, message))
}

pub fn bad_request(message: impl Into<String>) -> Resp {
    json_response(
        StatusCode::BAD_REQUEST,
        &ApiResponse::<serde_json::Value>::error(message),
    )
}

pub fn unauthorized(message: impl Into<String>) -> Resp {
    json_response(
        StatusCode::UNAUTHORIZED,
        &ApiResponse::<serde_json::Value>::error(message),
    )
}

pub fn forbidden(message: impl Into<String>) -> Resp {
    json_response(
        StatusCode::FORBIDDEN,
        &ApiResponse::<serde_json::Value>::error(message),
    )
}

pub fn internal_error(message: impl Into<String>) -> Resp {
    json_response(
        StatusCode::INTERNAL_SERVER_ERROR,
        &ApiResponse::<serde_json::Value>::error(message),
    )
}

pub fn method_not_allowed(message: &str) -> Resp {
    json_response(
        StatusCode::METHOD_NOT_ALLOWED,
        &ApiResponse::<serde_json::Value>::error(message),
    )
}

pub fn not_found(message: impl Into<String>) -> Resp {
    json_response(
        StatusCode::NOT_FOUND,
        &ApiResponse::<serde_json::Value>::error(message),
    )
}

pub fn controller_error(error: ControllerError) -> Resp {
    if let Some(conflict) = error.conflict {
        return json_response(
            StatusCode::CONFLICT,
            &ApiResponse::<serde_json::Value>::conflict(
                error.message,
                serde_json::to_value(conflict).unwrap_or_default(),
            ),
        );
    }
    internal_error(error.message)
}

pub fn plain(status: StatusCode, body: Vec<u8>, content_type: &str) -> Resp {
    let mut response = Response::new(Full::new(Bytes::from(body)));
    *response.status_mut() = status;
    if let Ok(value) = hyper::header::HeaderValue::from_str(content_type) {
        response
            .headers_mut()
            .insert(hyper::header::CONTENT_TYPE, value);
    }
    response
}

pub fn plain_text(status: StatusCode, message: &str) -> Resp {
    plain(
        status,
        message.as_bytes().to_vec(),
        "text/plain; charset=utf-8",
    )
}

pub fn attachment(body: Vec<u8>, content_type: &str, filename: &str) -> Resp {
    let mut response = plain(StatusCode::OK, body, content_type);
    if let Ok(value) =
        hyper::header::HeaderValue::from_str(&format!("attachment; filename=\"{filename}\""))
    {
        response
            .headers_mut()
            .insert(hyper::header::CONTENT_DISPOSITION, value);
    }
    response
}

pub fn extract_token(ctx: &Ctx<'_>) -> String {
    if let Some(value) = ctx.header("authorization") {
        if let Some(token) = value.strip_prefix("Bearer ") {
            return token.to_string();
        }
    }
    if let Some(token) = ctx.header("x-api-token") {
        if !token.is_empty() {
            return token.to_string();
        }
    }
    ctx.query_get("token").unwrap_or("").to_string()
}

pub fn verified(server: &Server, ctx: &Ctx<'_>) -> bool {
    server.verify_token(&extract_token(ctx), ctx.remote, ctx.headers)
}

pub fn client_ip(ctx: &Ctx<'_>) -> String {
    ctx.remote.ip().to_string()
}

pub fn is_loopback(ctx: &Ctx<'_>) -> bool {
    ctx.remote.ip().is_loopback()
}

pub fn header_trusted_origin(ctx: &Ctx<'_>) -> bool {
    let origin = ctx.header("origin").unwrap_or("");
    crate::cors::is_trusted_origin(origin, ctx.header("host"))
}
