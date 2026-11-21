use std::collections::HashMap;
use std::sync::Arc;

use chrono::{Datelike, Local, Timelike};
use hyper::http::Method;
use serde::{Deserialize, Serialize};
use serde_json::json;

use diting_desktop_api::config::{BlockingSchedule, FilterConfig, FilterList};
use diting_desktop_app::controller::filter::{
    qtype_from_name, CheckDomainRequest, ConfigureBlockedServicesRequest, ConfigureScheduleRequest,
    FilterActionRequest, FilterPauseRequest, UpdateRulesRequest,
};
use diting_services_core::catalog::{CATALOG, CATEGORIES};

use crate::handlers::cache::merge_patch;
use crate::handlers::{bad_request, internal_error, ok, ok_message, Ctx, Resp};
use crate::server::Server;
use crate::ws::Event;

const MAX_PAUSE_SECONDS: i64 = 10 * 365 * 24 * 3600;

pub fn handle_stats(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().filter_stats())
}

pub async fn handle_config(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().filter_config()),
        Method::POST => {
            let config: FilterConfig =
                match merge_patch(&server.runtime().filter_config(), ctx.body) {
                    Ok(config) => config,
                    Err(error) => return bad_request(format!("解析配置失败: {error}")),
                };
            let runtime = Arc::clone(server.runtime());
            match tokio::task::spawn_blocking(move || runtime.update_filter_config(config)).await {
                Ok(Ok(())) => ok_message("过滤配置已更新生效"),
                Ok(Err(error)) => internal_error(error.message),
                Err(error) => internal_error(format!("更新过滤配置失败: {error}")),
            }
        }
        _ => crate::handlers::method_not_allowed("不支持的 HTTP 方法"),
    }
}

pub fn handle_lists(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::GET], "只支持 GET 请求") {
        return response;
    }
    ok(server.runtime().filter_lists())
}

pub async fn handle_list_add(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let list: FilterList = match ctx.json() {
        Ok(list) => list,
        Err(response) => return response,
    };
    if list.url.trim().is_empty() {
        return bad_request("订阅源 URL 不能为空");
    }
    match server.runtime().add_filter_list(list).await {
        Ok(()) => ok_message("订阅源已成功添加"),
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_list_update(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let list: FilterList = match ctx.json() {
        Ok(list) => list,
        Err(response) => return response,
    };
    if list.id.trim().is_empty() {
        return bad_request("订阅源 ID 不能为空");
    }
    if list.url.trim().is_empty() {
        return bad_request("订阅源 URL 不能为空");
    }
    match server.runtime().update_filter_list(list).await {
        Ok(()) => ok_message("订阅源已成功更新"),
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_list_delete(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: FilterActionRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    match server.runtime().delete_filter_list(&request.id).await {
        Ok(()) => ok_message("订阅源已成功删除"),
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_list_refresh(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: FilterActionRequest = ctx.json_or_default().unwrap_or_default();
    match server.runtime().refresh_filter_lists(&request.id).await {
        Ok(()) => ok_message("规则源拉取与索引重构已完成"),
        Err(error) => internal_error(error.message),
    }
}

pub async fn handle_rules(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().custom_rules()),
        Method::POST => {
            let request: UpdateRulesRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            let runtime = Arc::clone(server.runtime());
            match tokio::task::spawn_blocking(move || runtime.set_custom_rules(request.rules)).await
            {
                Ok(Ok(())) => ok_message("自定义规则已保存生效"),
                Ok(Err(error)) => internal_error(error.message),
                Err(error) => internal_error(format!("保存自定义规则失败: {error}")),
            }
        }
        _ => crate::handlers::method_not_allowed("不支持的 HTTP 方法"),
    }
}

pub fn handle_check(server: &Server, ctx: &Ctx<'_>) -> Resp {
    if let Err(response) = ctx.require_method(&[Method::POST], "只支持 POST 请求") {
        return response;
    }
    let request: CheckDomainRequest = match ctx.json() {
        Ok(request) => request,
        Err(response) => return response,
    };
    let qtype = qtype_from_name(&request.qtype);
    ok(server.runtime().check_host_rule(&request.domain, qtype))
}

pub async fn handle_schedule(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().blocking_schedule()),
        Method::POST => {
            let request: ConfigureScheduleRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            let runtime = Arc::clone(server.runtime());
            let result =
                tokio::task::spawn_blocking(move || runtime.configure_blocking_schedule(request))
                    .await;
            match result {
                Ok(Ok(())) => ok_message("时间计划已更新并生效"),
                Ok(Err(error)) => internal_error(error.message),
                Err(error) => internal_error(format!("更新时间计划失败: {error}")),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET / POST 请求"),
    }
}

pub fn handle_pause(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(server.runtime().filter_pause()),
        Method::POST => {
            let request: FilterPauseRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            if request.paused && request.duration_sec < 0 {
                return bad_request("durationSec 不能为负数");
            }
            if request.paused && request.duration_sec > MAX_PAUSE_SECONDS {
                return bad_request(format!(
                    "durationSec 超出上限（最大 {MAX_PAUSE_SECONDS} 秒，约 10 年）"
                ));
            }
            match server.runtime().set_filter_pause(&request) {
                Ok(()) => {
                    let state = if request.paused { "paused" } else { "resumed" };
                    server.hub().broadcast(Event::new("filter", json!(state)));
                    ok_message(if request.paused {
                        "拦截已暂停"
                    } else {
                        "拦截已恢复"
                    })
                }
                Err(error) => internal_error(error.message),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET / POST 请求"),
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BlockedService {
    id: String,
    name: String,
    group: String,
    rules: Vec<String>,
    #[serde(rename = "ruleCount")]
    rule_count: usize,
    source: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BlockedServiceGroup {
    id: String,
    name: String,
    count: usize,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ServiceScheduleState {
    service_id: String,
    active: bool,
    has_schedule: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    active_name: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BlockedServicesResponse {
    services: Vec<BlockedService>,
    groups: Vec<BlockedServiceGroup>,
    blocked_ids: Vec<String>,
    blocked_groups: Vec<String>,
    active_rules: usize,
    schedules: HashMap<String, Vec<BlockingSchedule>>,
    schedule_states: Vec<ServiceScheduleState>,
}

fn category_name(id: &str) -> &'static str {
    match id {
        "social" => "社交",
        "video" => "视频",
        "messaging" => "消息",
        "gaming" => "游戏",
        "ads" => "广告",
        _ => "其他",
    }
}

fn blocked_services_response(server: &Server) -> BlockedServicesResponse {
    let state = server.runtime().blocked_services_state();
    let services: Vec<BlockedService> = CATALOG
        .iter()
        .map(|service| BlockedService {
            id: service.id.to_string(),
            name: service.name.to_string(),
            group: service.category.to_string(),
            rules: service
                .domains
                .iter()
                .map(|domain| domain.to_string())
                .collect(),
            rule_count: service.domains.len(),
            source: "builtin".to_string(),
        })
        .collect();
    let groups = CATEGORIES
        .iter()
        .map(|category| BlockedServiceGroup {
            id: category.to_string(),
            name: category_name(category).to_string(),
            count: CATALOG
                .iter()
                .filter(|service| service.category == *category)
                .count(),
        })
        .collect();
    let schedule_states = state
        .schedules
        .iter()
        .map(|(service_id, schedules)| schedule_state(service_id, schedules))
        .collect();
    BlockedServicesResponse {
        services,
        groups,
        blocked_ids: state.blocked_ids,
        blocked_groups: state.blocked_groups,
        active_rules: state.active_rules,
        schedules: state.schedules,
        schedule_states,
    }
}

fn weekdays_mask(days: &[String]) -> u8 {
    if days.is_empty() {
        return 0x7f;
    }
    let mut mask = 0u8;
    for day in days {
        let key: String = day.trim().to_lowercase().chars().take(3).collect();
        let index = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
            .iter()
            .position(|candidate| *candidate == key);
        if let Some(index) = index {
            mask |= 1 << index;
        }
    }
    mask
}

fn schedule_active(schedule: &BlockingSchedule) -> bool {
    if !schedule.enabled {
        return false;
    }
    let parse = |raw: &str| -> Option<i32> {
        let (hour, minute) = raw.trim().split_once(':')?;
        Some(hour.trim().parse::<i32>().ok()? * 60 + minute.trim().parse::<i32>().ok()?)
    };
    let (Some(start), Some(end)) = (parse(&schedule.start), parse(&schedule.end)) else {
        return false;
    };
    if start == end {
        return false;
    }
    let now = Local::now();
    let minute = now.hour() as i32 * 60 + now.minute() as i32;
    let mask = weekdays_mask(&schedule.weekdays);
    let today = 1u8 << now.weekday().num_days_from_sunday();
    if start < end {
        minute >= start && minute < end && mask & today != 0
    } else if minute >= start {
        mask & today != 0
    } else if minute < end {
        let yesterday = (now.weekday().num_days_from_sunday() + 6) % 7;
        mask & (1u8 << yesterday) != 0
    } else {
        false
    }
}

fn schedule_state(service_id: &str, schedules: &[BlockingSchedule]) -> ServiceScheduleState {
    let has_schedule = schedules.iter().any(|schedule| schedule.enabled);
    let active = !has_schedule || schedules.iter().any(schedule_active);
    let active_name = schedules
        .iter()
        .find(|schedule| schedule_active(schedule))
        .map(|schedule| schedule.name.clone())
        .unwrap_or_default();
    ServiceScheduleState {
        service_id: service_id.to_string(),
        active,
        has_schedule,
        active_name,
    }
}

pub async fn handle_services(server: &Server, ctx: &Ctx<'_>) -> Resp {
    match *ctx.method {
        Method::GET => ok(blocked_services_response(server)),
        Method::POST => {
            let request: ConfigureBlockedServicesRequest = match ctx.json() {
                Ok(request) => request,
                Err(response) => return response,
            };
            let runtime = Arc::clone(server.runtime());
            let result =
                tokio::task::spawn_blocking(move || runtime.configure_blocked_services(request))
                    .await;
            match result {
                Ok(Ok(())) => ok(blocked_services_response(server)),
                Ok(Err(error)) => internal_error(error.message),
                Err(error) => internal_error(format!("更新服务拦截配置失败: {error}")),
            }
        }
        _ => crate::handlers::method_not_allowed("只支持 GET, POST 请求"),
    }
}
