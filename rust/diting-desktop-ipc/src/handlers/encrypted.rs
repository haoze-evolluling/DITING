//! `/api/v1/encrypted/*`: status, configuration, certificates and profiles.

use base64::Engine;
use hyper::header::HeaderValue;
use hyper::http::{Method, StatusCode};
use serde::Deserialize;

use diting_desktop_app::controller::encrypted::{
    ConfigureACLRequest, ConfigureEncryptedDNSRequest, GenerateCertRequest, ImportCertRequest,
    CERT_IMPORT_MODE_PKCS12,
};

use crate::handlers::{bad_request, internal_error, ok, verified, Ctx, Resp};
use crate::server::Server;

fn write_status(server: &Server, message: &str) -> Resp {
    crate::handlers::ok_data_message(server.runtime().encrypted_dns_status(), message)
}

pub fn handle_status(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().encrypted_dns_status())
}

pub async fn handle_configure(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: ConfigureEncryptedDNSRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_encrypted_dns(request) {
        Ok(()) => {
            server.runtime().reload_encrypted().await;
            write_status(server, "加密 DNS 配置已更新")
        }
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_cert_generate(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: GenerateCertRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().generate_encrypted_cert(request) {
        Ok(()) => {
            server.runtime().reload_encrypted().await;
            write_status(server, "证书已生成")
        }
        Err(error) => bad_request(error.message),
    }
}

#[derive(Debug, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ImportCertPayload {
    #[serde(default)]
    mode: String,
    #[serde(default)]
    cert_pem: String,
    #[serde(default)]
    key_pem: String,
    #[serde(default)]
    data: String,
    #[serde(default)]
    password: String,
}

pub async fn handle_cert_import(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let payload: ImportCertPayload = match ctx.json() {
        Ok(payload) => payload,
        Err(response) => return response,
    };
    let data = if payload.mode == CERT_IMPORT_MODE_PKCS12 {
        match base64::engine::general_purpose::STANDARD.decode(payload.data.as_bytes()) {
            Ok(data) => data,
            Err(error) => {
                return bad_request(format!("PKCS#12 内容不是合法的 base64: {error}"));
            }
        }
    } else {
        Vec::new()
    };
    let request = ImportCertRequest {
        mode: payload.mode,
        cert_pem: payload.cert_pem,
        key_pem: payload.key_pem,
        data,
        password: payload.password,
    };
    match server.runtime().import_encrypted_cert(request) {
        Ok(()) => {
            server.runtime().reload_encrypted().await;
            write_status(server, "证书已导入")
        }
        Err(error) => bad_request(error.message),
    }
}

pub async fn handle_acl(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().encrypted_dns_status()),
        Method::POST => {
            let request: ConfigureACLRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            match server.runtime().configure_encrypted_acl(request) {
                Ok(()) => {
                    // The trusted-proxy list is baked into the listeners at start time.
                    server.runtime().reload_encrypted().await;
                    write_status(server, "反向代理可信来源已更新")
                }
                Err(error) => bad_request(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET 与 POST 请求"),
    }
}

pub fn handle_mobileconfig(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET, Method::HEAD], "只支持 GET 请求")
    {
        return response;
    }
    if !verified(server, ctx) {
        return crate::handlers::plain_text(
            StatusCode::UNAUTHORIZED,
            "unauthorized: missing or invalid authentication token",
        );
    }
    let protocol = ctx.query_get("protocol").unwrap_or("");
    let config = match server.runtime().build_mobile_config(protocol) {
        Ok(config) => config,
        Err(error) => return crate::handlers::plain_text(StatusCode::BAD_REQUEST, &error.message),
    };

    let mut response = hyper::Response::new(http_body_util::Full::new(hyper::body::Bytes::from(
        if *ctx.method == Method::HEAD {
            Vec::new()
        } else {
            config.data.clone()
        },
    )));
    *response.status_mut() = StatusCode::OK;
    let headers = response.headers_mut();
    if let Ok(value) = HeaderValue::from_str(config.content_type) {
        headers.insert(hyper::header::CONTENT_TYPE, value);
    }
    headers.insert(
        hyper::header::CONTENT_DISPOSITION,
        HeaderValue::from_static("attachment; filename=\"diting-dns.mobileconfig\""),
    );
    if let Ok(value) = HeaderValue::from_str(&config.data.len().to_string()) {
        headers.insert(hyper::header::CONTENT_LENGTH, value);
    }
    headers.insert(
        hyper::header::CACHE_CONTROL,
        HeaderValue::from_static("no-store"),
    );
    response
}
