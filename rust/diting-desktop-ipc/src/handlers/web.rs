//! `/api/v1/web/*` — the remote console's own status and firewall.

use hyper::http::Method;

use diting_desktop_app::controller::web::{ConfigureFirewallRequest, ConfigureWebRequest};

use crate::handlers::{internal_error, ok, ok_message, Ctx, Resp};
use crate::server::Server;

pub async fn handle_status(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    let initialized = server.auth().is_initialized();
    let username = server.auth().username();
    ok(server.runtime().web_status(initialized, &username).await)
}

pub async fn handle_configure(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: ConfigureWebRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_web(request).await {
        Ok(()) => ok_message("局域网 Web 远程管理配置已保存并生效"),
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_firewall(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: ConfigureFirewallRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server
        .runtime()
        .configure_web_firewall(request.enable)
        .await
    {
        Ok(()) => ok_message(if request.enable {
            "已成功放行 Web 端口防火墙入站规则"
        } else {
            "已清除 Web 端口防火墙规则"
        }),
        Err(error) => internal_error(error.message),
    }
}
