use serde::{Deserialize, Serialize};

use diting_desktop_api::config::QueryLogConfig;
use diting_desktop_core::querylog::{
    Config as QueryLogSettings, HourPoint, NameCount, SearchQuery, SearchResult, Summary,
};

use crate::controller::ControllerError;
use crate::AppRuntime;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct QueryStatsResponse {
    pub summary: Summary,
    pub per_hour: Vec<HourPoint>,
    pub top_domains: Vec<NameCount>,
    pub top_blocked: Vec<NameCount>,
    pub top_clients: Vec<NameCount>,
}

fn to_api_config(config: &QueryLogSettings) -> QueryLogConfig {
    QueryLogConfig {
        enabled: config.enabled,
        max_entries: config.max_entries,
        file_enabled: config.file_enabled,
        retention_days: config.retention_days,
        log_clients: config.log_clients,
        data_dir: config.data_dir.clone(),
    }
}

fn to_core_config(config: &QueryLogConfig) -> QueryLogSettings {
    QueryLogSettings {
        enabled: config.enabled,
        max_entries: config.max_entries,
        file_enabled: config.file_enabled,
        retention_days: config.retention_days,
        log_clients: config.log_clients,
        data_dir: config.data_dir.clone(),
    }
}

impl AppRuntime {
    pub fn query_log(&self, query: SearchQuery) -> SearchResult {
        self.querylog.search(query)
    }

    pub fn query_stats(&self) -> QueryStatsResponse {
        const TOP_N: i64 = 10;
        QueryStatsResponse {
            summary: self.querylog.stats(),
            per_hour: self.querylog.per_hour(),
            top_domains: self.querylog.top_domains(TOP_N),
            top_blocked: self.querylog.top_blocked_domains(TOP_N),
            top_clients: self.querylog.top_clients(TOP_N),
        }
    }

    pub fn clear_query_log(&self) -> Result<(), ControllerError> {
        self.querylog
            .clear(true)
            .map_err(|error| ControllerError::new(error.to_string()))
    }

    pub fn query_log_config(&self) -> QueryLogConfig {
        to_api_config(&self.querylog.config())
    }

    pub fn update_query_log_config(
        &self,
        mut config: QueryLogConfig,
    ) -> Result<(), ControllerError> {
        config.normalize();
        self.querylog.configure(to_core_config(&config));
        let effective = to_api_config(&self.querylog.config());
        self.update_config(|next| next.query_log = effective)
            .map(|_| ())
            .map_err(ControllerError::new)
    }
}
