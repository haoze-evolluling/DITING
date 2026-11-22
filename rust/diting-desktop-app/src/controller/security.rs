use serde::Deserialize;

use diting_desktop_api::config::{
    AccessControlConfig, DNS64Config, ECSConfig, HostsConfig, RateLimitConfig, RebindConfig,
};

use crate::controller::ControllerError;
use crate::AppRuntime;

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureAccessRequest {
    #[serde(default)]
    pub allowed_clients: Vec<String>,
    #[serde(default)]
    pub blocked_clients: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureRateLimitRequest {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub rate: f64,
    #[serde(default)]
    pub burst: i32,
    #[serde(default)]
    pub ipv4_prefix: i32,
    #[serde(default)]
    pub ipv6_prefix: i32,
    #[serde(default)]
    pub exempt_ips: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureDNS64Request {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub prefixes: Vec<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureBlockUnqualifiedRequest {
    #[serde(default)]
    pub block_unqualified: bool,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigurePrivacyRequest {
    #[serde(default, rename = "enableEDE")]
    pub enable_ede: Option<bool>,
    #[serde(default, rename = "blockPrivatePTR")]
    pub block_private_ptr: Option<bool>,
    #[serde(default, rename = "blockIPv6")]
    pub block_ipv6: Option<bool>,
    #[serde(default, rename = "blockECH")]
    pub block_ech: Option<bool>,
    #[serde(default, rename = "ednsPadding")]
    pub edns_padding: Option<i32>,
    #[serde(default, rename = "blockANY")]
    pub block_any: Option<bool>,
    #[serde(default, rename = "blockANYMode")]
    pub block_any_mode: Option<String>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureRebindRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub allowed_domains: Option<Vec<String>>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureHostsRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default)]
    pub use_system_host: Option<bool>,
    #[serde(default)]
    pub custom_files: Option<Vec<String>>,
    #[serde(default)]
    pub ttl: Option<u32>,
}

#[derive(Debug, Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConfigureECSRequest {
    #[serde(default)]
    pub enabled: Option<bool>,
    #[serde(default, rename = "stripECS")]
    pub strip_ecs: Option<bool>,
    #[serde(default)]
    pub custom_subnet: Option<String>,
}

impl AppRuntime {
    pub fn configure_access(&self, request: ConfigureAccessRequest) -> Result<(), ControllerError> {
        self.update_config(|config| {
            config.access = AccessControlConfig {
                allowed_clients: request.allowed_clients,
                blocked_clients: request.blocked_clients,
            };
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn configure_rate_limit(
        &self,
        request: ConfigureRateLimitRequest,
    ) -> Result<(), ControllerError> {
        self.update_config(|config| {
            config.rate_limit = RateLimitConfig {
                enabled: request.enabled,
                rate: request.rate,
                burst: request.burst,
                ipv4_prefix: request.ipv4_prefix,
                ipv6_prefix: request.ipv6_prefix,
                exempt_ips: request.exempt_ips,
            };
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn configure_dns64(&self, request: ConfigureDNS64Request) -> Result<(), ControllerError> {
        self.update_config(|config| {
            config.dns64 = DNS64Config {
                enabled: request.enabled,
                prefixes: request.prefixes,
            };
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn configure_block_unqualified(
        &self,
        request: ConfigureBlockUnqualifiedRequest,
    ) -> Result<(), ControllerError> {
        self.update_config(|config| config.dns.block_unqualified = request.block_unqualified)
            .map(|_| ())
            .map_err(ControllerError::new)
    }

    pub fn configure_privacy(
        &self,
        request: ConfigurePrivacyRequest,
    ) -> Result<(), ControllerError> {
        self.update_config(|config| {
            if let Some(value) = request.enable_ede {
                config.dns.enable_ede = value;
            }
            if let Some(value) = request.block_private_ptr {
                config.dns.block_private_ptr = value;
            }
            if let Some(value) = request.block_ipv6 {
                config.dns.block_ipv6 = value;
            }
            if let Some(value) = request.block_ech {
                config.dns.block_ech = value;
            }
            if let Some(value) = request.edns_padding {
                let padding = value.max(0);
                config.dns.edns_padding = padding;
                config.upstream.edns_padding = padding;
            }
            if let Some(value) = request.block_any {
                config.dns.block_any = value;
            }
            if let Some(value) = request.block_any_mode {
                config.dns.block_any_mode = if value == "rfc8482" {
                    "rfc8482".to_string()
                } else {
                    "notimp".to_string()
                };
            }
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn configure_rebind(&self, request: ConfigureRebindRequest) -> Result<(), ControllerError> {
        self.update_config(|config| {
            if let Some(enabled) = request.enabled {
                config.rebind.enabled = enabled;
            }
            if let Some(domains) = request.allowed_domains {
                config.rebind.allowed_domains = domains;
            }
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn configure_hosts(&self, request: ConfigureHostsRequest) -> Result<(), ControllerError> {
        if let Some(ttl) = request.ttl {
            if ttl == 0 {
                return Err(ControllerError::new("TTL 必须为正整数"));
            }
        }
        self.update_config(|config| {
            if let Some(enabled) = request.enabled {
                config.hosts.enabled = enabled;
            }
            if let Some(system) = request.use_system_host {
                config.hosts.use_system_host = system;
            }
            if let Some(files) = request.custom_files {
                config.hosts.custom_files = files;
            }
            if let Some(ttl) = request.ttl {
                config.hosts.ttl = ttl;
            }
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn configure_ecs(&self, request: ConfigureECSRequest) -> Result<(), ControllerError> {
        self.update_config(|config| {
            if let Some(enabled) = request.enabled {
                config.ecs.enabled = enabled;
            }
            if let Some(strip) = request.strip_ecs {
                config.ecs.strip_ecs = strip;
            }
            if let Some(subnet) = request.custom_subnet {
                config.ecs.custom_subnet = subnet;
            }
        })
        .map(|_| ())
        .map_err(ControllerError::new)
    }

    pub fn hosts_config(&self) -> HostsConfig {
        self.config().hosts
    }

    pub fn rebind_config(&self) -> RebindConfig {
        self.config().rebind
    }

    pub fn access_config(&self) -> AccessControlConfig {
        self.config().access
    }

    pub fn rate_limit_config(&self) -> RateLimitConfig {
        self.config().rate_limit
    }

    pub fn dns64_config(&self) -> DNS64Config {
        self.config().dns64
    }

    pub fn ecs_config(&self) -> ECSConfig {
        self.config().ecs
    }
}
