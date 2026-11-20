use crate::ipclass::{is_loopback_or_internal, is_unspecified};

pub const MODE_FULL_UDP: u8 = 0;
pub const MODE_FULL_TCP: u8 = 1;
pub const MODE_MITM_TCP: u8 = 2;

pub const ACTION_BLOCK_UID: u8 = 0;
pub const ACTION_BLOCK_APP_ALLOWLIST: u8 = 1;
pub const ACTION_BLOCK_ENCRYPTED_DNS: u8 = 2;
pub const ACTION_BLOCK_QUIC: u8 = 3;
pub const ACTION_DROP_UNSPECIFIED: u8 = 4;
pub const ACTION_HANDLE_DNS: u8 = 5;
pub const ACTION_RELAY: u8 = 6;
pub const ACTION_INTERCEPT: u8 = 7;

pub const FLAG_LOG_CONNECTION: u32 = 1 << 8;

pub const PORT_DNS: u16 = 53;
pub const PORT_HTTPS: u16 = 443;
pub const PORT_HTTP: u16 = 80;

#[derive(Debug, Clone, Copy, Default)]
pub struct FlowInput<'a> {
    pub uid_blocked: bool,
    pub app_allowlist_allowed: bool,
    pub encrypted_dns_blocked: bool,
    pub quic_drop: bool,
    pub quic_uid_selected: bool,
    pub mitm_uid_allowed: bool,
    pub port: u16,
    pub ip: &'a [u8],
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Decision {
    pub action: u8,
    pub log_connection: bool,
}

impl Decision {
    pub fn new(action: u8, log_connection: bool) -> Self {
        Decision {
            action,
            log_connection,
        }
    }

    pub fn to_u32(self) -> u32 {
        self.action as u32
            | if self.log_connection {
                FLAG_LOG_CONNECTION
            } else {
                0
            }
    }

    pub fn from_u32(raw: u32) -> Self {
        Decision {
            action: (raw & 0xff) as u8,
            log_connection: raw & FLAG_LOG_CONNECTION != 0,
        }
    }
}

pub fn admit(mode: u8, input: &FlowInput) -> Decision {
    match mode {
        MODE_FULL_TCP => full_tcp(input),
        MODE_MITM_TCP => mitm_tcp(input),
        _ => full_udp(input),
    }
}

fn full_udp(input: &FlowInput) -> Decision {
    if input.uid_blocked {
        return Decision::new(ACTION_BLOCK_UID, false);
    }
    if input.port == PORT_DNS {
        return Decision::new(ACTION_HANDLE_DNS, false);
    }
    if input.encrypted_dns_blocked {
        return Decision::new(ACTION_BLOCK_ENCRYPTED_DNS, false);
    }
    if !input.app_allowlist_allowed {
        return Decision::new(ACTION_BLOCK_APP_ALLOWLIST, false);
    }
    if input.quic_drop && input.port == PORT_HTTPS && input.quic_uid_selected {
        return Decision::new(ACTION_BLOCK_QUIC, true);
    }
    Decision::new(ACTION_RELAY, true)
}

fn full_tcp(input: &FlowInput) -> Decision {
    if input.uid_blocked {
        return Decision::new(ACTION_BLOCK_UID, false);
    }
    if !input.app_allowlist_allowed {
        return Decision::new(ACTION_BLOCK_APP_ALLOWLIST, false);
    }
    if input.port == PORT_DNS {
        return Decision::new(ACTION_HANDLE_DNS, false);
    }
    if input.encrypted_dns_blocked {
        return Decision::new(ACTION_BLOCK_ENCRYPTED_DNS, false);
    }
    Decision::new(ACTION_RELAY, true)
}

fn mitm_tcp(input: &FlowInput) -> Decision {
    if input.uid_blocked {
        return Decision::new(ACTION_BLOCK_UID, false);
    }
    if !input.app_allowlist_allowed {
        return Decision::new(ACTION_BLOCK_APP_ALLOWLIST, false);
    }
    if is_unspecified(input.ip) {
        return Decision::new(ACTION_DROP_UNSPECIFIED, false);
    }
    if input.encrypted_dns_blocked {
        return Decision::new(ACTION_BLOCK_ENCRYPTED_DNS, true);
    }
    if input.port == PORT_DNS {
        return Decision::new(ACTION_HANDLE_DNS, true);
    }
    if is_loopback_or_internal(input.ip) {
        return Decision::new(ACTION_RELAY, true);
    }
    if input.port != PORT_HTTPS && input.port != PORT_HTTP {
        return Decision::new(ACTION_RELAY, true);
    }
    if !input.mitm_uid_allowed {
        return Decision::new(ACTION_RELAY, true);
    }
    Decision::new(ACTION_INTERCEPT, true)
}

#[cfg(test)]
mod tests;
