use std::sync::Arc;

use chrono::{Local, TimeZone};
use hyper::header::{HeaderName, HeaderValue};
use hyper::http::Method;

use diting_desktop_api::config::QueryLogConfig;
use diting_desktop_core::querylog::{Record, SearchQuery};

use crate::handlers::cache::merge_patch;
use crate::handlers::{attachment, bad_request, internal_error, ok, ok_message, Ctx, Resp};
use crate::server::Server;

const EXPORT_PAGE_SIZE: i64 = 500;
const MAX_EXPORT_RECORDS: usize = 50_000;

const CSV_HEADERS: [&str; 17] = [
    "时间",
    "域名",
    "类型",
    "状态",
    "响应码",
    "客户端 IP",
    "客户端名称",
    "耗时(ms)",
    "缓存",
    "TTL",
    "缓存详情",
    "已拦截",
    "匹配规则",
    "拦截原因",
    "协议",
    "上游",
    "错误",
];

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

pub async fn handle_search(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    let query = search_query(ctx);
    let runtime = Arc::clone(server.runtime());
    match tokio::task::spawn_blocking(move || runtime.query_log(query)).await {
        Ok(result) => ok(result),
        Err(error) => internal_error(format!("查询日志检索失败: {error}")),
    }
}

fn collect_export_records(
    runtime: &diting_desktop_app::AppRuntime,
    query: SearchQuery,
) -> (Vec<Record>, i64) {
    let mut records = Vec::new();
    let mut offset = 0i64;
    let mut total = 0i64;
    loop {
        let mut page = query.clone();
        page.limit = EXPORT_PAGE_SIZE;
        page.offset = offset;
        let result = runtime.query_log(page);
        if offset == 0 {
            total = result.total;
        }
        if result.entries.is_empty() {
            break;
        }
        records.extend(result.entries);
        offset += EXPORT_PAGE_SIZE;
        if offset >= total || records.len() >= MAX_EXPORT_RECORDS {
            break;
        }
    }
    records.truncate(MAX_EXPORT_RECORDS);
    (records, total)
}

fn format_time(timestamp_ms: i64) -> String {
    Local
        .timestamp_millis_opt(timestamp_ms)
        .single()
        .map(|time| time.format("%Y-%m-%d %H:%M:%S").to_string())
        .unwrap_or_default()
}

fn status_label(status: &str) -> &'static str {
    if status.eq_ignore_ascii_case("blocked") {
        "拦截"
    } else if status.eq_ignore_ascii_case("cached") {
        "缓存"
    } else if status.eq_ignore_ascii_case("stale") {
        "过期缓存"
    } else if status.eq_ignore_ascii_case("error") {
        "失败"
    } else {
        "允许"
    }
}

fn yes_no(value: bool) -> &'static str {
    if value {
        "是"
    } else {
        "否"
    }
}

fn csv_field(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}

fn csv_line(fields: &[String]) -> String {
    let mut line = fields
        .iter()
        .map(|field| csv_field(field))
        .collect::<Vec<_>>()
        .join(",");
    line.push_str("\r\n");
    line
}

fn csv_body(records: &[Record]) -> String {
    let headers = CSV_HEADERS
        .iter()
        .map(|header| header.to_string())
        .collect::<Vec<_>>();
    let mut body = String::with_capacity(records.len() * 128);
    body.push('\u{feff}');
    body.push_str(&csv_line(&headers));
    for record in records {
        let fields = vec![
            format_time(record.timestamp),
            record.domain.clone(),
            record.qtype.clone(),
            status_label(&record.status).to_string(),
            record.rcode.clone(),
            record.client_ip.clone(),
            record.client_name.clone(),
            format!("{:.1}", record.duration_ms),
            yes_no(record.cached).to_string(),
            record.ttl.map(|ttl| ttl.to_string()).unwrap_or_default(),
            record.cache_hit.clone(),
            yes_no(record.blocked).to_string(),
            record.filter_rule.clone(),
            record.filter_reason.clone(),
            record.protocol.clone(),
            record.upstream_provider.clone(),
            record.error.clone(),
        ];
        body.push_str(&csv_line(&fields));
    }
    body
}

fn export_response(mut response: Resp, exported: usize, truncated: bool) -> Resp {
    let headers = response.headers_mut();
    headers.insert(
        HeaderName::from_static("x-diting-export-count"),
        HeaderValue::from_str(&exported.to_string())
            .unwrap_or_else(|_| HeaderValue::from_static("0")),
    );
    headers.insert(
        HeaderName::from_static("x-diting-export-truncated"),
        HeaderValue::from_static(if truncated { "true" } else { "false" }),
    );
    response
}

pub async fn handle_export(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    let format = ctx
        .query_get("format")
        .unwrap_or("csv")
        .trim()
        .to_ascii_lowercase();
    if format != "csv" && format != "json" {
        return bad_request("导出格式仅支持 csv 或 json");
    }
    let mut query = search_query(ctx);
    query.include_file = true;
    let runtime = Arc::clone(server.runtime());

    let (records, total) =
        match tokio::task::spawn_blocking(move || collect_export_records(&runtime, query)).await {
            Ok(collected) => collected,
            Err(error) => return internal_error(format!("导出查询日志失败: {error}")),
        };
    let exported = records.len();
    let truncated = (exported as i64) < total;
    let stamp = Local::now().format("%Y%m%d-%H%M%S").to_string();

    let response = if format == "json" {
        let payload = serde_json::json!({
            "exportedAt": Local::now().format("%Y-%m-%d %H:%M:%S").to_string(),
            "exported": exported,
            "truncated": truncated,
            "entries": records,
        });
        match serde_json::to_vec(&payload) {
            Ok(body) => attachment(
                body,
                "application/json; charset=utf-8",
                &format!("DITING-querylog-{stamp}.json"),
            ),
            Err(error) => return internal_error(format!("序列化导出内容失败: {error}")),
        }
    } else {
        attachment(
            csv_body(&records).into_bytes(),
            "text/csv; charset=utf-8",
            &format!("DITING-querylog-{stamp}.csv"),
        )
    };
    export_response(response, exported, truncated)
}

pub fn handle_stats(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().query_stats())
}

pub async fn handle_clear(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let runtime = Arc::clone(server.runtime());
    match tokio::task::spawn_blocking(move || runtime.clear_query_log()).await {
        Ok(Ok(())) => ok_message("查询历史与统计已成功清空"),
        Ok(Err(error)) => internal_error(error.message),
        Err(error) => internal_error(format!("清空查询日志失败: {error}")),
    }
}

pub async fn handle_config(server: &Server, ctx: &Ctx<'_>) -> Resp {
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
            let runtime = Arc::clone(server.runtime());
            match tokio::task::spawn_blocking(move || runtime.update_query_log_config(config)).await
            {
                Ok(Ok(())) => ok_message("查询日志配置已更新并生效"),
                Ok(Err(error)) => internal_error(error.message),
                Err(error) => internal_error(format!("更新查询日志配置失败: {error}")),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET / POST 请求"),
    }
}
