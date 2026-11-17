//! `/api/v1/dns/rewrite/*` and `/api/v1/dns/zone/*`.

use hyper::http::Method;

use diting_desktop_api::config::RewriteRule;
use diting_desktop_app::controller::rewrite_zone::{
    ConfigureRewriteRequest, ConfigureZoneRequest, ZoneTestRequest,
};

use crate::handlers::{bad_request, internal_error, ok, ok_message, Ctx, Resp};
use crate::response::ApiResponse;
use crate::server::Server;

pub fn handle_rules(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().rewrite_rules()),
        Method::POST => {
            let rule: RewriteRule = match ctx.json() {
                Ok(rule) => rule,
                Err(response) => return response,
            };
            match server.runtime().add_rewrite_rule(rule) {
                Ok(()) => ok_message("DNS 重写规则已成功添加或更新"),
                Err(error) => bad_request(error.message),
            }
        }
        Method::DELETE => {
            let mut domain = ctx.query_get("domain").unwrap_or("").to_string();
            if domain.is_empty() {
                if let Ok(value) = serde_json::from_slice::<serde_json::Value>(ctx.body) {
                    domain = value
                        .get("domain")
                        .and_then(|value| value.as_str())
                        .unwrap_or("")
                        .to_string();
                }
            }
            if domain.is_empty() {
                return bad_request("缺少 domain 参数");
            }
            match server.runtime().delete_rewrite_rule(&domain) {
                Ok(()) => ok_message("DNS 重写规则已成功删除"),
                Err(error) => internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET, POST, DELETE 请求"),
    }
}

pub fn handle_configure(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: ConfigureRewriteRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().configure_rewrite(request) {
        Ok(()) => ok_message("DNS 重写全局配置已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_zone_config(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().zone_config()),
        Method::POST => {
            let request: ConfigureZoneRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            match server.runtime().configure_zone(request) {
                Ok(()) => ok(server.runtime().zone_config()),
                Err(error) => internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET, POST 请求"),
    }
}

pub fn handle_zone_test(_server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: ZoneTestRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    let result = _server.runtime().zone_test(request);
    // Parse failures are expected user input; the envelope still reports success.
    crate::handlers::json_response(hyper::http::StatusCode::OK, &ApiResponse::ok(result))
}
