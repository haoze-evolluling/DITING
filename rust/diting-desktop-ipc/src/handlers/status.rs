use hyper::http::Method;
use serde_json::json;

use diting_desktop_app::controller::status::AdapterTakeoverRequest;

use crate::handlers::{controller_error, internal_error, ok, ok_message, Ctx, Resp};
use crate::server::Server;
use crate::types::{AutofixPortRequest, MetaResponse};
use crate::ws::Event;

pub fn handle_health(_ctx: &Ctx<'_>) -> Resp {
    ok("ok")
}

pub fn handle_meta(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    let runtime = server.runtime();
    let backend = runtime.storage_backend();
    ok(MetaResponse {
        os: runtime.platform_name(),
        storage_backend: backend.to_string(),
        database_path: (backend == "sqlite").then(|| runtime.storage_location()),
    })
}

pub async fn handle_status(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    ok(server.runtime().status())
}

pub async fn handle_dns_start(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    match server.runtime().start_dns_checked().await {
        Ok(()) => {
            server.hub().broadcast(&Event::new("dns", json!("started")));
            ok_message("DNS 服务已成功启动")
        }
        Err(error) => controller_error(error),
    }
}

pub async fn handle_dns_stop(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    match server.runtime().stop_dns_checked().await {
        Ok(()) => {
            server.hub().broadcast(&Event::new("dns", json!("stopped")));
            ok_message("DNS 服务已停止")
        }
        Err(error) => controller_error(error),
    }
}

pub async fn handle_takeover_enable(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    match server.runtime().enable_takeover().await {
        Ok(()) => {
            server
                .hub()
                .broadcast(&Event::new("takeover", json!("enabled")));
            ok_message("物理网卡 DNS 已成功接管")
        }
        Err(error) => controller_error(error),
    }
}

pub async fn handle_takeover_disable(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    match server.runtime().disable_takeover().await {
        Ok(()) => {
            server
                .hub()
                .broadcast(&Event::new("takeover", json!("disabled")));
            ok_message("系统 DNS 接管已还原")
        }
        Err(error) => controller_error(error),
    }
}

pub async fn handle_adapters(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    match server.runtime().adapters().await {
        Ok(adapters) => ok(adapters),
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_adapter_takeover(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: AdapterTakeoverRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().set_adapter_takeover(request.clone()).await {
        Ok(()) => {
            server
                .hub()
                .broadcast(&Event::new("takeover", json!(request)));
            ok_message("网卡接管状态已更新")
        }
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_emergency_restore(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    match server.runtime().emergency_restore().await {
        Ok(result) => ok(result),
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_port_check(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    match server.runtime().port_check().await {
        Ok(result) => ok(result),
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_port_autofix(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "method not allowed") {
        return response;
    }
    let request: AutofixPortRequest = match ctx.json_or_default() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().port_autofix(request.start_dns).await {
        Ok(result) => {
            if request.start_dns && result.available {
                server.hub().broadcast(&Event::new("dns", json!("started")));
            }
            crate::handlers::ok_data_message(result, "端口冲突已成功自动修复")
        }
        Err(error) => controller_error(error),
    }
}

pub async fn handle_service_status(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "method not allowed") {
        return response;
    }
    match server.runtime().core_service_status().await {
        Ok(status) => ok(status),
        Err(error) => internal_error(error.message),
    }
}
