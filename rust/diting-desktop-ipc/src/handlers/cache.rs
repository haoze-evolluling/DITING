//! `/api/v1/cache/*`.

use hyper::http::Method;
use serde::de::DeserializeOwned;
use serde::Serialize;
use serde_json::Value;

use diting_desktop_api::config::CacheConfig;

use crate::handlers::{bad_request, internal_error, ok, ok_message, Ctx, Resp};
use crate::server::Server;

fn parse_limit(ctx: &Ctx<'_>, default: i32) -> i32 {
    ctx.query_get("limit")
        .and_then(|value| value.parse::<i32>().ok())
        .filter(|value| *value > 0)
        .unwrap_or(default)
}

/// Merges a JSON patch into the serialized current value (Go unmarshals into a copy).
pub fn merge_patch<T: Serialize + DeserializeOwned>(current: &T, body: &[u8]) -> Result<T, String> {
    let mut base = serde_json::to_value(current).map_err(|error| error.to_string())?;
    let patch: Value = serde_json::from_slice(body).map_err(|error| error.to_string())?;
    match (&mut base, patch) {
        (Value::Object(base), Value::Object(patch)) => {
            for (key, value) in patch {
                base.insert(key, value);
            }
        }
        _ => return Err("请求体必须是 JSON 对象".to_string()),
    }
    serde_json::from_value(base).map_err(|error| error.to_string())
}

pub fn handle_stats(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().cache_stats())
}

pub fn handle_entries(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    let query = ctx
        .query_get("query")
        .filter(|value| !value.is_empty())
        .or_else(|| ctx.query_get("q"))
        .unwrap_or("");
    ok(server.runtime().cache_entries(query, parse_limit(ctx, 100)))
}

pub fn handle_top(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().cache_top_domains(parse_limit(ctx, 10)))
}

pub fn handle_clear(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    match server.runtime().clear_cache() {
        Ok(()) => ok_message("智能缓存已成功清空"),
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_config(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().cache_config()),
        Method::POST => {
            let config: CacheConfig = match merge_patch(&server.runtime().cache_config(), ctx.body)
            {
                Ok(config) => config,
                Err(error) => return bad_request(format!("解析缓存配置请求体失败: {error}")),
            };
            match server.runtime().update_cache_config(config) {
                Ok(()) => ok_message("智能缓存配置已更新并生效"),
                Err(error) => internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET / POST 请求"),
    }
}

pub fn handle_persist(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().cache_persist_status())
}

pub fn handle_dump(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    match server.runtime().dump_cache() {
        Ok(status) => {
            server.hub().broadcast(crate::ws::Event::new(
                "filter",
                serde_json::json!("cache_dumped"),
            ));
            crate::handlers::ok_data_message(status, "缓存已落盘")
        }
        Err(error) => internal_error(error.message),
    }
}

pub fn handle_load(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    match server.runtime().load_cache_from_disk() {
        Ok(status) => crate::handlers::ok_data_message(status, "缓存已从落盘文件恢复"),
        Err(error) => internal_error(error.message),
    }
}
