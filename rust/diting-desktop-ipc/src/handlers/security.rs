//! `/api/v1/dns/{access,ratelimit,dns64,unqualified,privacy,rebind,hosts,ecs}/configure`.

use hyper::http::Method;

use diting_desktop_app::controller::security::{
    ConfigureAccessRequest, ConfigureBlockUnqualifiedRequest, ConfigureDNS64Request,
    ConfigureECSRequest, ConfigureHostsRequest, ConfigurePrivacyRequest, ConfigureRateLimitRequest,
    ConfigureRebindRequest,
};

use crate::handlers::{internal_error, ok_message, Ctx, Resp};
use crate::server::Server;

fn post_only(ctx: &Ctx<'_>) -> Option<Resp> {
    ctx.require_method(&[Method::POST], "只支持 POST 请求")
        .err()
}

pub fn handle_access(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Some(response) = post_only(ctx) {
        return response;
    }
    let request: ConfigureAccessRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_access(request) {
        Ok(()) => ok_message("客户端访问控制配置已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_rate_limit(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Some(response) = post_only(ctx) {
        return response;
    }
    let request: ConfigureRateLimitRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_rate_limit(request) {
        Ok(()) => ok_message("客户端请求速率限制配置已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_dns64(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Some(response) = post_only(ctx) {
        return response;
    }
    let request: ConfigureDNS64Request = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_dns64(request) {
        Ok(()) => ok_message("DNS64 过渡合成配置已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_unqualified(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Some(response) = post_only(ctx) {
        return response;
    }
    let request: ConfigureBlockUnqualifiedRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_block_unqualified(request) {
        Ok(()) => ok_message("单标签域名防外泄配置已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_privacy(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Some(response) = post_only(ctx) {
        return response;
    }
    let request: ConfigurePrivacyRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_privacy(request) {
        Ok(()) => ok_message("DNS 隐私与协议增强配置已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_rebind(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Some(response) = post_only(ctx) {
        return response;
    }
    let request: ConfigureRebindRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_rebind(request) {
        Ok(()) => ok_message("DNS Rebinding 防御配置已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_hosts(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Some(response) = post_only(ctx) {
        return response;
    }
    let request: ConfigureHostsRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_hosts(request) {
        Ok(()) => ok_message("Hosts 解析器配置已成功更新"),
        Err(error) => crate::handlers::bad_request(error.message),
    }
}

pub fn handle_ecs(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Some(response) = post_only(ctx) {
        return response;
    }
    let request: ConfigureECSRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_ecs(request) {
        Ok(()) => ok_message("EDNS Client Subnet 配置已成功更新"),
        Err(error) => internal_error(error.message),
    }
}
