//! `/api/v1/querylog/*`.

use hyper::http::Method;

use diting_desktop_api::config::QueryLogConfig;
use diting_desktop_core::querylog::SearchQuery;

use crate::handlers::cache::merge_patch;
use crate::handlers::{bad_request, internal_error, ok, ok_message, Ctx, Resp};
use crate::server::Server;

fn search_query(ctx: &Ctx<'_>) -> SearchQuery {
    let include_file = !matches!(ctx.query_get("includeFile"), Some("0") | Some("false"));
    SearchQuery {
        domain: ctx.query_get("domain").unwrap_or("").to_string(),
        client: ctx.query_get("client").unwrap_or("").to_string(),
        qtype: ctx.query_get("qtype").unwrap_or("").to_string(),
        rcode: ctx.query_get("rcode").unwrap_or("").to_string(),
        status: ctx.query_get("status").unwrap_or("").to_string(),
        start_ms: ctx
            .query_get("startMs")
            .and_then(|value| value.parse().ok())
            .unwrap_or(0),
        end_ms: ctx
            .query_get("endMs")
            .and_then(|value| value.parse().ok())
            .unwrap_or(0),
        limit: ctx
            .query_get("limit")
            .and_then(|value| value.parse().ok())
            .unwrap_or(0),
        offset: ctx
            .query_get("offset")
            .and_then(|value| value.parse().ok())
            .unwrap_or(0),
        include_file,
    }
}

pub fn handle_search(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().query_log(search_query(ctx)))
}

pub fn handle_stats(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().query_stats())
}

pub fn handle_clear(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    match server.runtime().clear_query_log() {
        Ok(()) => ok_message("查询历史与统计已成功清空"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_config(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().query_log_config()),
        Method::POST => {
            let config: QueryLogConfig =
                match merge_patch(&server.runtime().query_log_config(), ctx.body) {
                    Ok(config) => config,
                    Err(error) => {
                        return bad_request(format!("解析查询日志配置请求体失败: {error}"))
                    }
                };
            match server.runtime().update_query_log_config(config) {
                Ok(()) => ok_message("查询日志配置已更新并生效"),
                Err(error) => internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET / POST 请求"),
    }
}
