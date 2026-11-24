use serde::{Deserialize, Serialize};

pub const OPENWRT_MODE_REPLACE_DNSMASQ: &str = "replace_dnsmasq";
pub const OPENWRT_MODE_DNSMASQ_UPSTREAM: &str = "dnsmasq_upstream";
pub const DEFAULT_DNSMASQ_AUX_PORT: u16 = 5353;
pub const DEFAULT_UPSTREAM_LISTEN_PORT: u16 = 5354;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(default, rename_all = "camelCase")]
pub struct OpenWrtConfig {
    pub mode: String,
    pub dnsmasq_port: u16,
    pub upstream_port: u16,
    pub forward_local_domain: bool,
    pub force_redirect_53: bool,
    pub desired_active: bool,
}

impl Default for OpenWrtConfig {
    fn default() -> Self {
        Self {
            mode: OPENWRT_MODE_REPLACE_DNSMASQ.to_string(),
            dnsmasq_port: DEFAULT_DNSMASQ_AUX_PORT,
            upstream_port: DEFAULT_UPSTREAM_LISTEN_PORT,
            forward_local_domain: true,
            force_redirect_53: false,
            desired_active: false,
        }
    }
}

impl OpenWrtConfig {
    pub fn is_replace_mode(&self) -> bool {
        !self
            .mode
            .trim()
            .eq_ignore_ascii_case(OPENWRT_MODE_DNSMASQ_UPSTREAM)
    }

    pub fn normalize(&mut self) {
        let mode = self.mode.trim().to_ascii_lowercase();
        self.mode = if mode == OPENWRT_MODE_DNSMASQ_UPSTREAM {
            OPENWRT_MODE_DNSMASQ_UPSTREAM.to_string()
        } else {
            OPENWRT_MODE_REPLACE_DNSMASQ.to_string()
        };

        if self.dnsmasq_port == 0 || self.dnsmasq_port == 53 {
            self.dnsmasq_port = DEFAULT_DNSMASQ_AUX_PORT;
        }
        if self.upstream_port == 0 || self.upstream_port == 53 {
            self.upstream_port = DEFAULT_UPSTREAM_LISTEN_PORT;
        }
        if self.upstream_port == self.dnsmasq_port {
            self.upstream_port = if self.dnsmasq_port == DEFAULT_UPSTREAM_LISTEN_PORT {
                5355
            } else {
                DEFAULT_UPSTREAM_LISTEN_PORT
            };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_invalid_modes_and_ports() {
        let mut cfg = OpenWrtConfig {
            mode: "DNSmasq_Upstream".to_string(),
            dnsmasq_port: 53,
            upstream_port: 5353,
            forward_local_domain: true,
            force_redirect_53: true,
            desired_active: false,
        };
        cfg.normalize();
        assert_eq!(cfg.mode, OPENWRT_MODE_DNSMASQ_UPSTREAM);
        assert_eq!(cfg.dnsmasq_port, DEFAULT_DNSMASQ_AUX_PORT);
        assert_eq!(cfg.upstream_port, DEFAULT_UPSTREAM_LISTEN_PORT);

        cfg.mode = "unknown".to_string();
        cfg.dnsmasq_port = 5354;
        cfg.upstream_port = 5354;
        cfg.normalize();
        assert_eq!(cfg.mode, OPENWRT_MODE_REPLACE_DNSMASQ);
        assert_eq!(cfg.upstream_port, 5355);
    }
}
