use base64::engine::general_purpose::{STANDARD, URL_SAFE};
use base64::Engine;
use hyper::header::HeaderValue;
use hyper::http::{Method, StatusCode};
use serde_json::json;

use diting_desktop_app::controller::background::SetLoginBackgroundInput;

use crate::handlers::{
    self, bad_request, client_ip, is_loopback, ok, ok_message, unauthorized, verified, Ctx, Resp,
};
use crate::server::Server;
use crate::types::{
    AuthStatusResponse, ChangePasswordRequest, LoginRequest, LoginResponse,
    SetLoginBackgroundRequest, SetupAuthRequest,
};
use crate::ws::Event;

fn persist_credentials(server: &Server, username: &str, hash: &str, salt: &str) {
    let _ = server.runtime().update_config(|config| {
        config.web.username = username.to_string();
        config.web.password_hash = hash.to_string();
        config.web.salt = salt.to_string();
    });
}

pub fn handle_status(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    let (locked, remaining) = server.auth().lockout(&client_ip(ctx));
    ok(AuthStatusResponse {
        initialized: server.auth().is_initialized(),
        web_enabled: server.runtime().config().web.enabled,
        authenticated: false,
        username: server.auth().username(),
        locked,
        lockout_remaining_sec: remaining,
    })
}

pub fn handle_login(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: LoginRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server
        .auth()
        .login(&request.username, &request.password, &client_ip(ctx))
    {
        Ok(session) => ok(LoginResponse {
            token: session.token,
            username: session.username,
            expires_at: session.expires_at_unix,
        }),
        Err(error) => unauthorized(error),
    }
}

pub fn handle_logout(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let token = handlers::extract_token(ctx);
    server.auth().revoke_session(&token);
    ok_message("已成功注销登录会话")
}

pub fn handle_setup(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: SetupAuthRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.auth().setup(&request.username, &request.password) {
        Ok((username, hash, salt)) => {
            persist_credentials(server, &username, &hash, &salt);
            ok_message("管理员账号初始化成功！")
        }
        Err(error) => bad_request(error),
    }
}

pub fn handle_password(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: ChangePasswordRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    let token = handlers::extract_token(ctx);
    let ipc_token = server.ipc_config().auth_token;
    let bypass = (!ipc_token.is_empty() && token == ipc_token)
        || (ipc_token.is_empty() && is_loopback(ctx) && handlers::header_trusted_origin(ctx));
    match server.auth().update_credentials(
        &request.username,
        &request.old_password,
        &request.new_password,
        bypass,
    ) {
        Ok((username, hash, salt)) => {
            persist_credentials(server, &username, &hash, &salt);
            ok_message("管理员密码修改成功！已有外部会话已失效。")
        }
        Err(error) => bad_request(error),
    }
}

fn background_permission(
    server: &Server,
    ctx: &Ctx<'_>,
    body_password: &str,
) -> Result<(), String> {
    if is_loopback(ctx) || verified(server, ctx) || !server.auth().is_initialized() {
        return Ok(());
    }
    let admin_password = ctx
        .header("x-admin-password")
        .filter(|value| !value.is_empty())
        .unwrap_or(body_password);
    if admin_password.is_empty() {
        return Err("未授权：局域网远程修改全局背景需要验证管理员密码".to_string());
    }
    match server
        .auth()
        .verify_password_with_ip(&client_ip(ctx), admin_password)
    {
        Ok(true) => Ok(()),
        Ok(false) => Err("未授权：管理员密码验证失败".to_string()),
        Err(error) => Err(error),
    }
}

fn decode_data_url(url: &str) -> Result<Option<Vec<u8>>, String> {
    if !url.starts_with("data:image/") {
        return Ok(None);
    }
    let Some((_, raw)) = url.split_once(',') else {
        return Err("无效的图片 Data URL 数据格式".to_string());
    };
    let cleaned: String = raw
        .chars()
        .filter(|ch| !matches!(ch, ' ' | '\n' | '\r' | '\t'))
        .collect();
    let bytes = STANDARD
        .decode(cleaned.as_bytes())
        .or_else(|_| URL_SAFE.decode(cleaned.as_bytes()))
        .map_err(|error| format!("图片 Base64 解码失败: {error}"))?;
    if bytes.is_empty() {
        return Err("图片数据内容为空".to_string());
    }
    Ok(Some(bytes))
}

pub fn handle_background(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().login_background()),
        Method::POST | Method::PUT => {
            let request: SetLoginBackgroundRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            if let Err(error) = background_permission(server, ctx, &request.admin_password) {
                return unauthorized(error);
            }
            let image = match decode_data_url(request.url.trim()) {
                Ok(image) => image,
                Err(error) => return bad_request(error),
            };
            let input = SetLoginBackgroundInput {
                kind: request.kind,
                url: request.url,
                opacity: request.opacity,
                blur: request.blur,
                image,
            };
            match server.runtime().set_login_background(input) {
                Ok(response) => {
                    server
                        .hub()
                        .broadcast(Event::new("background", json!("updated")));
                    handlers::ok_data_message(response, "全局登录背景已保存并应用")
                }
                Err(error) => bad_request(error.message),
            }
        }
        Method::DELETE => {
            let password = ctx
                .query_get("adminPassword")
                .or_else(|| ctx.header("x-admin-password"))
                .unwrap_or("");
            if let Err(error) = background_permission(server, ctx, password) {
                return unauthorized(error);
            }
            match server.runtime().reset_login_background() {
                Ok(response) => {
                    server
                        .hub()
                        .broadcast(Event::new("background", json!("reset")));
                    handlers::ok_data_message(response, "已恢复系统默认背景")
                }
                Err(error) => crate::handlers::internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("method not allowed"),
    }
}

pub fn handle_background_image(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET, Method::HEAD], "method not allowed") {
        return response;
    }
    let Some(image) = server.runtime().login_background_image() else {
        return handlers::plain_text(StatusCode::NOT_FOUND, "not found");
    };
    let etag = format!("\"bg-{}-{}\"", image.data.len(), image.modified_millis);
    if ctx.header("if-none-match") == Some(etag.as_str()) {
        let mut response =
            hyper::Response::new(http_body_util::Full::new(hyper::body::Bytes::new()));
        *response.status_mut() = StatusCode::NOT_MODIFIED;
        return response;
    }

    let body = if *ctx.method == Method::HEAD {
        Vec::new()
    } else {
        image.data.clone()
    };
    let mut response =
        hyper::Response::new(http_body_util::Full::new(hyper::body::Bytes::from(body)));
    *response.status_mut() = StatusCode::OK;
    let headers = response.headers_mut();
    if let Ok(value) = HeaderValue::from_str(&image.content_type) {
        headers.insert(hyper::header::CONTENT_TYPE, value);
    }
    if let Ok(value) = HeaderValue::from_str(&etag) {
        headers.insert(hyper::header::ETAG, value);
    }
    headers.insert(
        hyper::header::CACHE_CONTROL,
        HeaderValue::from_static("public, max-age=86400"),
    );
    if let Ok(value) = HeaderValue::from_str(&image.data.len().to_string()) {
        headers.insert(hyper::header::CONTENT_LENGTH, value);
    }
    response
}
