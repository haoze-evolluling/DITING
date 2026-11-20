use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use diting_desktop_api::config::{BlockingSchedule, FilterConfig, FilterList};
use diting_desktop_core::filter::{CheckHostResult, PauseState, RewriteResult};

use crate::controller::ControllerError;
use crate::AppRuntime;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FilterStats {
    pub enabled: bool,
    pub total_rules: u32,
    pub active_lists: i32,
    pub total_queries: u64,
    pub blocked_queries: u64,
    pub allowed_queries: u64,
    pub block_rate: f64,
    pub schedule_active: bool,
    pub paused: bool,
    pub paused_remaining_sec: i64,
    pub paused_until_ms: i64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewriteRecordDto {
    #[serde(rename = "type")]
    pub kind: String,
    pub value: String,
    pub ttl: u32,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RewriteResultDto {
    pub rcode: u8,
    pub records: Vec<RewriteRecordDto>,
    pub summary: Vec<String>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckHostResponse {
    pub blocked: bool,
    pub action: String,
    pub matched_rule: String,
    pub list_name: String,
    pub reason: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub rewritten: Option<RewriteResultDto>,
}

impl From<CheckHostResult> for CheckHostResponse {
    fn from(result: CheckHostResult) -> Self {
        Self {
            blocked: result.blocked,
            action: result.action.as_str().to_string(),
            matched_rule: result.matched_rule,
            list_name: result.list_name,
            reason: result.reason,
            rewritten: result.rewritten.map(rewrite_dto),
        }
    }
}

fn rewrite_dto(result: RewriteResult) -> RewriteResultDto {
    RewriteResultDto {
        rcode: result.rcode,
        records: result
            .records
            .into_iter()
            .map(|record| RewriteRecordDto {
                kind: record.kind,
                value: record.value,
                ttl: record.ttl,
            })
            .collect(),
        summary: result.summary,
    }
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FilterListsResponse {
    pub total: i32,
    pub lists: Vec<FilterList>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FilterRulesResponse {
    pub rules: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FilterActionRequest {
    #[serde(default)]
    pub id: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateRulesRequest {
    #[serde(default)]
    pub rules: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckDomainRequest {
    #[serde(default)]
    pub domain: String,
    #[serde(default, rename = "qtype")]
    pub qtype: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ScheduleConfigResponse {
    pub enabled: bool,
    pub schedules: Vec<BlockingSchedule>,
    pub active: bool,
    pub active_id: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureScheduleRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub schedules: Option<Vec<BlockingSchedule>>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FilterPauseRequest {
    #[serde(default)]
    pub paused: bool,
    #[serde(default)]
    pub duration_sec: i64,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FilterPauseResponse {
    pub paused: bool,
    pub remaining_seconds: i64,
    pub paused_until_ms: i64,
    pub blocking_enabled: bool,
}

impl From<PauseState> for FilterPauseResponse {
    fn from(state: PauseState) -> Self {
        Self {
            paused: state.paused,
            remaining_seconds: state.remaining_sec,
            paused_until_ms: state.until_ms.unwrap_or(0),
            blocking_enabled: false,
        }
    }
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureBlockedServicesRequest {
    #[serde(default)]
    pub ids: Option<Vec<String>>,
    #[serde(default)]
    pub groups: Option<Vec<String>>,
    #[serde(default)]
    pub schedules: Option<HashMap<String, Vec<BlockingSchedule>>>,
}

#[derive(Debug, Clone, Default)]
pub struct BlockedServicesState {
    pub blocked_ids: Vec<String>,
    pub blocked_groups: Vec<String>,
    pub active_rules: usize,
    pub schedules: HashMap<String, Vec<BlockingSchedule>>,
}

pub fn qtype_from_name(name: &str) -> u16 {
    match name.trim().to_ascii_uppercase().as_str() {
        "" | "A" => 1,
        "NS" => 2,
        "CNAME" => 5,
        "SOA" => 6,
        "PTR" => 12,
        "MX" => 15,
        "TXT" => 16,
        "AAAA" => 28,
        "SRV" => 33,
        "HTTPS" => 65,
        "SVCB" => 64,
        "ANY" => 255,
        _ => 1,
    }
}

impl AppRuntime {
    pub fn filter_stats(&self) -> FilterStats {
        let stats = self.filter.stats();
        FilterStats {
            enabled: stats.enabled,
            total_rules: stats.total_rules,
            active_lists: stats.active_lists,
            total_queries: stats.total_queries,
            blocked_queries: stats.blocked_queries,
            allowed_queries: stats.allowed_queries,
            block_rate: stats.block_rate,
            schedule_active: stats.schedule_active,
            paused: stats.paused,
            paused_remaining_sec: stats.paused_remaining_sec,
            paused_until_ms: stats.paused_until_ms,
        }
    }

    pub fn filter_config(&self) -> FilterConfig {
        self.filter.config()
    }

    pub fn update_filter_config(&self, config: FilterConfig) -> Result<(), ControllerError> {
        self.filter.configure(config);
        let normalized = self.filter.config();
        self.update_config(|next| next.filter = normalized)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    pub fn filter_lists(&self) -> FilterListsResponse {
        let lists = self.filter.config().lists;
        FilterListsResponse {
            total: lists.len() as i32,
            lists,
        }
    }

    pub async fn add_filter_list(&self, list: FilterList) -> Result<(), ControllerError> {
        self.filter
            .add_list(list)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))?;
        self.persist_filter_engine()
    }

    pub async fn update_filter_list(&self, list: FilterList) -> Result<(), ControllerError> {
        self.filter
            .update_list(list)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))?;
        self.persist_filter_engine()
    }

    pub async fn delete_filter_list(&self, id: &str) -> Result<(), ControllerError> {
        self.filter
            .delete_list(id)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))?;
        self.persist_filter_engine()
    }

    pub async fn refresh_filter_lists(&self, id: &str) -> Result<(), ControllerError> {
        self.filter
            .refresh_lists(id)
            .await
            .map_err(|error| ControllerError::new(error.to_string()))?;
        self.persist_filter_engine()
    }

    fn persist_filter_engine(&self) -> Result<(), ControllerError> {
        let config = self.filter.config();
        self.update_config(|next| next.filter = config)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    pub fn custom_rules(&self) -> FilterRulesResponse {
        FilterRulesResponse {
            rules: self.filter.config().custom_rules,
        }
    }

    pub fn set_custom_rules(&self, rules: Vec<String>) -> Result<(), ControllerError> {
        self.update_config(|next| next.filter.custom_rules = rules)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    pub fn check_host_rule(&self, domain: &str, qtype: u16) -> CheckHostResponse {
        self.filter.check_host(domain, qtype).into()
    }

    pub fn blocking_schedule(&self) -> ScheduleConfigResponse {
        let config = self.filter.config();
        ScheduleConfigResponse {
            enabled: config.schedule_enabled,
            schedules: config.schedules,
            active: self.filter.is_blocking_active(),
            active_id: self
                .filter
                .current_schedule()
                .map(|schedule| schedule.id)
                .unwrap_or_default(),
        }
    }

    pub fn configure_blocking_schedule(
        &self,
        request: ConfigureScheduleRequest,
    ) -> Result<(), ControllerError> {
        self.update_config(|next| {
            if let Some(enabled) = request.enabled {
                next.filter.schedule_enabled = enabled;
            }
            if let Some(schedules) = request.schedules {
                next.filter.schedules = schedules;
            }
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn filter_pause(&self) -> FilterPauseResponse {
        let mut response = FilterPauseResponse::from(self.filter.pause_state());
        response.blocking_enabled = self.filter.config().enabled;
        response
    }

    pub fn set_filter_pause(&self, request: &FilterPauseRequest) -> Result<(), ControllerError> {
        if request.paused && request.duration_sec < 0 {
            return Err(ControllerError::new("durationSec 不能为负数"));
        }
        self.filter.set_paused(request.paused, request.duration_sec);
        Ok(())
    }

    pub fn blocked_services_state(&self) -> BlockedServicesState {
        let config = self.filter.config();
        let active_rules = self
            .filter
            .count_service_rules(&config.blocked_services, &config.blocked_service_groups);
        BlockedServicesState {
            blocked_ids: config.blocked_services,
            blocked_groups: config.blocked_service_groups,
            active_rules,
            schedules: config.service_schedules,
        }
    }

    pub fn configure_blocked_services(
        &self,
        request: ConfigureBlockedServicesRequest,
    ) -> Result<(), ControllerError> {
        self.update_config(|next| {
            if let Some(ids) = request.ids {
                next.filter.blocked_services = ids;
            }
            if let Some(groups) = request.groups {
                next.filter.blocked_service_groups = groups;
            }
            if let Some(schedules) = request.schedules {
                next.filter.service_schedules = schedules;
            }
            next.filter.normalize();
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }
}
