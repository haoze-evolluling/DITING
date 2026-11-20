use hyper::http::Method;
use serde_json::json;

use diting_desktop_app::controller::web::{ConfigureFirewallRequest, ConfigureLANRequest};

use crate::handlers::{internal_error, ok, ok_data_message, ok_message, Ctx, Resp};
use crate::server::Server;
use crate::ws::Event;

pub async fn handle_status(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    ok(server.runtime().lan_status().await)
}

pub async fn handle_configure(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: ConfigureLANRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_lan(request).await {
        Ok(()) => {
            server
                .hub()
                .broadcast(Event::new("dns", json!("lan_updated")));
            ok_message("局域网 DNS 服务配置已更新")
        }
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
    match server.runtime().configure_firewall(request.enable).await {
        Ok(()) => {
            let message = if request.enable {
                "已成功放行 53 端口防火墙规则"
            } else {
                "已成功移除 53 端口防火墙规则"
            };
            ok_data_message(message, message)
        }
        Err(error) => internal_error(error.message),
    }
}
