//! DNS rewrite rules and local authoritative zones.

use serde::{Deserialize, Serialize};

use diting_desktop_api::config::{RewriteRule, ZoneConfig, ZoneEntry};
use diting_desktop_core::zone::{
    ZoneEngine, MAX_ZONE_CONTENT_BYTES, MAX_ZONE_COUNT, MAX_ZONE_RECORDS,
};

use crate::controller::ControllerError;
use crate::AppRuntime;

/// `ipc.ConfigureRewriteRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureRewriteRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub ttl: Option<u32>,
    #[serde(default)]
    pub rules: Option<Vec<RewriteRule>>,
}

/// `ipc.ConfigureZoneRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureZoneRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub ttl: Option<u32>,
    #[serde(default)]
    pub zones: Option<Vec<ZoneEntry>>,
}

/// `ipc.ZoneTestRequest`.
#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ZoneTestRequest {
    #[serde(default)]
    pub origin: String,
    #[serde(default)]
    pub content: String,
    #[serde(default)]
    pub ttl: u32,
}

/// `ipc.ZoneTestResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ZoneTestResponse {
    pub success: bool,
    pub records: Vec<String>,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub error: String,
}

/// `core.ZoneState`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ZoneStateDto {
    pub id: String,
    pub origin: String,
    pub records: usize,
    pub loaded: bool,
    #[serde(skip_serializing_if = "String::is_empty")]
    pub error: String,
}

/// `ipc.ZoneConfigResponse`.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ZoneConfigResponse {
    pub enabled: bool,
    pub ttl: u32,
    pub zones: Vec<ZoneEntry>,
    pub states: Vec<ZoneStateDto>,
    pub record_count: usize,
    pub max_zones: usize,
    pub max_records: usize,
}

impl AppRuntime {
    pub fn rewrite_rules(&self) -> Vec<RewriteRule> {
        self.rewrite.rules()
    }

    pub fn add_rewrite_rule(&self, rule: RewriteRule) -> Result<(), ControllerError> {
        self.rewrite.add_rule(rule).map_err(ControllerError::new)?;
        let rules = self.rewrite.rules();
        self.update_config(|config| config.rewrite.rules = rules)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    pub fn delete_rewrite_rule(&self, domain: &str) -> Result<(), ControllerError> {
        self.rewrite
            .delete_rule(domain)
            .map_err(ControllerError::new)?;
        let rules = self.rewrite.rules();
        self.update_config(|config| config.rewrite.rules = rules)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    pub fn configure_rewrite(
        &self,
        request: ConfigureRewriteRequest,
    ) -> Result<(), ControllerError> {
        if let Some(ttl) = request.ttl {
            if ttl == 0 {
                return Err(ControllerError::new("TTL 必须为正整数"));
            }
        }
        self.update_config(|config| {
            if let Some(enabled) = request.enabled {
                config.rewrite.enabled = enabled;
            }
            if let Some(ttl) = request.ttl {
                config.rewrite.ttl = ttl;
            }
            if let Some(rules) = request.rules {
                config.rewrite.rules = rules;
            }
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    /// `GetZoneConfig`.
    pub fn zone_config(&self) -> ZoneConfigResponse {
        let config = self.config().zone;
        let states: Vec<ZoneStateDto> = self
            .zone
            .states()
            .into_iter()
            .map(|state| ZoneStateDto {
                id: state.id,
                origin: state.origin,
                records: state.records,
                loaded: state.loaded,
                error: state.error.unwrap_or_default(),
            })
            .collect();
        ZoneConfigResponse {
            enabled: config.enabled,
            ttl: config.ttl,
            zones: config.zones,
            record_count: states
                .iter()
                .filter(|state| state.loaded)
                .map(|state| state.records)
                .sum(),
            states,
            max_zones: MAX_ZONE_COUNT,
            max_records: MAX_ZONE_RECORDS,
        }
    }

    /// `ConfigureZone`.
    pub fn configure_zone(&self, request: ConfigureZoneRequest) -> Result<(), ControllerError> {
        if let Some(ttl) = request.ttl {
            if ttl == 0 {
                return Err(ControllerError::new("TTL 必须为正整数"));
            }
        }
        self.update_config(|config| {
            if let Some(enabled) = request.enabled {
                config.zone.enabled = enabled;
            }
            if let Some(ttl) = request.ttl {
                config.zone.ttl = ttl;
            }
            if let Some(zones) = request.zones {
                config.zone.zones = zones;
            }
            config.zone.normalize();
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    /// `ParseZonePreview`: validates through the real engine and previews the record lines.
    pub fn zone_test(&self, request: ZoneTestRequest) -> ZoneTestResponse {
        match preview_zone(&request) {
            Ok(records) => ZoneTestResponse {
                success: true,
                records,
                error: String::new(),
            },
            Err(error) => ZoneTestResponse {
                success: false,
                records: Vec::new(),
                error,
            },
        }
    }
}

fn preview_zone(request: &ZoneTestRequest) -> Result<Vec<String>, String> {
    let origin = request.origin.trim();
    if origin.is_empty() {
        return Err("区原点不能为空".to_string());
    }
    if request.content.len() > MAX_ZONE_CONTENT_BYTES {
        return Err(format!("区文本超过 {} 字节上限", MAX_ZONE_CONTENT_BYTES));
    }
    let ttl = if request.ttl > 0 { request.ttl } else { 300 };
    let config = ZoneConfig {
        enabled: true,
        ttl,
        zones: vec![ZoneEntry {
            id: "preview".to_string(),
            origin: origin.to_string(),
            content: request.content.clone(),
            enabled: true,
        }],
    };
    let engine = ZoneEngine::new(&config);
    let state = engine
        .states()
        .into_iter()
        .next()
        .ok_or_else(|| "区解析失败".to_string())?;
    if !state.loaded {
        return Err(state.error.unwrap_or_else(|| "区解析失败".to_string()));
    }

    let mut records = Vec::new();
    for line in request.content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with(';') || trimmed.starts_with('#') {
            continue;
        }
        if trimmed.starts_with('$') {
            continue;
        }
        records.push(trimmed.to_string());
    }
    Ok(records)
}
