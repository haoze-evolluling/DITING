use serde::{Deserialize, Serialize};

use diting_desktop_api::config::security::SAFESEARCH_SERVICES;
use diting_desktop_api::config::SafeSearchConfig;

use crate::controller::ControllerError;
use crate::AppRuntime;

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureSafeSearchRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub disabled: Option<Vec<String>>,
    #[serde(default)]
    pub ttl: Option<u32>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SafeSearchConfigResponse {
    pub enabled: bool,
    pub disabled: Vec<String>,
    pub ttl: u32,
}

fn normalize_disabled(disabled: Vec<String>) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    disabled
        .into_iter()
        .filter(|service| {
            SAFESEARCH_SERVICES.contains(&service.as_str()) && seen.insert(service.clone())
        })
        .collect()
}

impl AppRuntime {
    pub fn safe_search_config(&self) -> SafeSearchConfigResponse {
        let config = self.config().safe_search;
        SafeSearchConfigResponse {
            enabled: config.enabled,
            disabled: config.disabled,
            ttl: config.ttl,
        }
    }

    pub fn configure_safe_search(
        &self,
        request: ConfigureSafeSearchRequest,
    ) -> Result<(), ControllerError> {
        if let Some(ttl) = request.ttl {
            if ttl == 0 {
                return Err(ControllerError::new("TTL 必须为正整数"));
            }
        }
        self.update_config(|config| {
            let next = SafeSearchConfig {
                enabled: request.enabled.unwrap_or(config.safe_search.enabled),
                disabled: request
                    .disabled
                    .map(normalize_disabled)
                    .unwrap_or_else(|| config.safe_search.disabled.clone()),
                ttl: request.ttl.unwrap_or(config.safe_search.ttl),
            };
            config.safe_search = next;
            config.safe_search.normalize();
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }
}
