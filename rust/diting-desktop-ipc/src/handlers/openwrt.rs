use hyper::http::Method;
use serde_json::json;

use diting_desktop_app::controller::openwrt::ConfigureOpenWrtRequest;

use crate::handlers::{controller_error, ok, ok_data_message, Ctx, Resp};
use crate::server::Server;
use crate::ws::Event;

pub async fn handle_status(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    ok(server.runtime().openwrt_status().await)
}

pub async fn handle_configure(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: ConfigureOpenWrtRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_openwrt(request).await {
        Ok(status) => {
            server
                .hub()
                .broadcast(&Event::new("takeover", json!("openwrt_updated")));
            server
                .hub()
                .broadcast(&Event::new("dns", json!("reconfigured")));
            ok_data_message(status, "OpenWrt 路由器 DNS 集成配置已保存并生效")
        }
        Err(error) => controller_error(error),
    }
}
