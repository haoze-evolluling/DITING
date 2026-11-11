//! The per-flow admission plan: the gate order of the three data-plane entry points.
//!
//! The old handlers interleaved the gates with logging and relay calls. The order differs per
//! entry point (UDP checks port 53 first, TCP checks the app allowlist first, MITM drops an
//! unspecified server address before anything else), so the mode is an explicit input. The plan
//! also carries the "log the connection first" bit: the log points are user-visible and moving
//! one would change which flows show up as connections.
//!
//! Go resolves every predicate that belongs to another kernel (blocked UID membership, the app
//! allowlist decision, the QUIC UID selection, the encrypted-DNS switch) and passes the booleans
//! in; those checks are side-effect free, so evaluating them eagerly does not change behaviour.

use crate::ipclass::{is_loopback_or_internal, is_unspecified};

/// `newFullTunnelUdpHandler`.
pub const MODE_FULL_UDP: u8 = 0;
/// `newFullPassthroughTcpHandler`.
pub const MODE_FULL_TCP: u8 = 1;
/// `newMitmTcpHandler`.
pub const MODE_MITM_TCP: u8 = 2;

/// `uid_blocked`.
pub const ACTION_BLOCK_UID: u8 = 0;
/// `app_allowlist_blocked`.
pub const ACTION_BLOCK_APP_ALLOWLIST: u8 = 1;
/// `blocked_encrypted_dns`.
pub const ACTION_BLOCK_ENCRYPTED_DNS: u8 = 2;
/// `quic_forced_tcp`.
pub const ACTION_BLOCK_QUIC: u8 = 3;
/// The MITM gate's "server address is unspecified" drop.
pub const ACTION_DROP_UNSPECIFIED: u8 = 4;
/// `handleDNSOverUdp` / `handleDNSOverTCP`.
pub const ACTION_HANDLE_DNS: u8 = 5;
/// Dial/relay directly (UDP dial, TCP direct relay, or the MITM early bypass).
pub const ACTION_RELAY: u8 = 6;
/// The MITM handler continues into peek/classify/local-asset/rewrite/blocking.
pub const ACTION_INTERCEPT: u8 = 7;

/// The caller must run `logConnection` before performing the action.
pub const FLAG_LOG_CONNECTION: u32 = 1 << 8;

/// `flowDialTimeout`-independent constants the gate order needs.
pub const PORT_DNS: u16 = 53;
/// `flow.serverPort == 443` is the HTTP/3 TCP fallback in the QUIC gate.
pub const PORT_HTTPS: u16 = 443;
/// The two ports the MITM handler intercepts.
pub const PORT_HTTP: u16 = 80;

/// Every predicate one flow needs. The booleans come from the other kernels / settings.
#[derive(Debug, Clone, Copy, Default)]
pub struct FlowInput<'a> {
    /// `isUIDBlocked(uid)`.
    pub uid_blocked: bool,
    /// `appAllowlistConnectionAllowed(uid, serverIP)`.
    pub app_allowlist_allowed: bool,
    /// `shouldBlockEncryptedDNS(serverPort)` — already includes the port check.
    pub encrypted_dns_blocked: bool,
    /// The `SetFilterHttp3` switch.
    pub quic_drop: bool,
    /// `filter.HasAllowedUIDs() && uid != UIDUnknown && filter.IsUIDAllowed(uid)`.
    pub quic_uid_selected: bool,
    /// `uid != UIDUnknown && filter.IsUIDAllowed(uid)`.
    pub mitm_uid_allowed: bool,
    /// `flow.serverPort`.
    pub port: u16,
    /// `flow.serverIP` as its raw 4/16 bytes (only the MITM mode reads it).
    pub ip: &'a [u8],
}

/// One admission verdict: an action plus whether the connection should be logged first.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Decision {
    pub action: u8,
    pub log_connection: bool,
}

impl Decision {
    /// Builds one verdict.
    pub fn new(action: u8, log_connection: bool) -> Self {
        Decision {
            action,
            log_connection,
        }
    }

    /// Packs into the `u32` the C ABI returns.
    pub fn to_u32(self) -> u32 {
        self.action as u32
            | if self.log_connection {
                FLAG_LOG_CONNECTION
            } else {
                0
            }
    }

    /// Reads the packed `u32`.
    pub fn from_u32(raw: u32) -> Self {
        Decision {
            action: (raw & 0xff) as u8,
            log_connection: raw & FLAG_LOG_CONNECTION != 0,
        }
    }
}

/// The gate order of one mode.
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
