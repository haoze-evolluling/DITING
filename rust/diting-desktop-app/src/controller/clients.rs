use serde::{Deserialize, Serialize};

use diting_desktop_api::config::{ClientAlias, ClientGroup};

use crate::controller::status::ClientSummary;
use crate::controller::ControllerError;
use crate::AppRuntime;

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureClientAliasRequest {
    #[serde(default)]
    pub ip: String,
    #[serde(default)]
    pub name: String,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureClientGroupsRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub groups: Option<Vec<ClientGroup>>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientGroupRuleListOption {
    pub id: String,
    pub name: String,
    pub enabled: bool,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientGroupUpstreamOption {
    pub id: String,
    pub protocol: String,
    pub server: String,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ClientGroupConfigResponse {
    pub enabled: bool,
    pub groups: Vec<ClientGroup>,
    pub rule_lists: Vec<ClientGroupRuleListOption>,
    pub upstreams: Vec<ClientGroupUpstreamOption>,
}

impl AppRuntime {
    pub fn clients(&self) -> Vec<ClientSummary> {
        crate::controller::status::client_summaries(self)
    }

    pub fn configure_client_alias(
        &self,
        request: ConfigureClientAliasRequest,
    ) -> Result<(), ControllerError> {
        if request.ip.trim().is_empty() {
            return Err(ControllerError::new("客户端 IP 不能为空"));
        }
        let ip = request.ip.trim().to_string();
        self.update_config(|config| {
            config.client.aliases.retain(|alias| alias.ip != ip);
            if !request.name.trim().is_empty() {
                config.client.aliases.push(ClientAlias {
                    ip,
                    name: request.name.trim().to_string(),
                });
            }
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn client_groups(&self) -> ClientGroupConfigResponse {
        let config = self.config();
        let rule_lists = config
            .filter
            .lists
            .iter()
            .map(|list| ClientGroupRuleListOption {
                id: list.id.clone(),
                name: list.name.clone(),
                enabled: list.enabled,
            })
            .collect();
        let upstreams = config
            .upstream
            .providers
            .iter()
            .map(|provider| ClientGroupUpstreamOption {
                id: provider.id.clone(),
                protocol: provider.protocol.to_ascii_uppercase(),
                server: if provider.server.is_empty() {
                    provider.url.clone()
                } else {
                    provider.server.clone()
                },
            })
            .collect();
        ClientGroupConfigResponse {
            enabled: config.client.groups_enabled,
            groups: config.client.groups,
            rule_lists,
            upstreams,
        }
    }

    pub fn configure_client_groups(
        &self,
        request: ConfigureClientGroupsRequest,
    ) -> Result<(), ControllerError> {
        self.update_config(|config| {
            if let Some(enabled) = request.enabled {
                config.client.groups_enabled = enabled;
            }
            if let Some(groups) = request.groups {
                config.client.groups = groups;
            }
            config.client.normalize();
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }
}
