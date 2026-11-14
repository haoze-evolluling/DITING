//! Flow admission and the connection log: the Go `gate.go` + `engine_connection_log.go` pair.
//!
//! The decision half is [`diting_gate_core`]: blocked UIDs, the encrypted-DNS port, the QUIC drop
//! and the per-mode order. This module supplies the predicates that belong to the engine's settings,
//! performs the action, and emits the same two log shapes the UI reads:
//!
//! * `connection` — every admitted flow, deduplicated on `app|dest|port|proto`;
//! * `firewall:<reason>` — every blocked one, `uid_blocked` / `blocked_encrypted_dns` /
//!   `quic_forced_tcp` / `app_allowlist_blocked`.
//!
//! Both rows carry the destination as `ips` and the package (or `uid:N`, or `unknown`) as `app`, in
//! the column order `DnsLogWriter` expects. The dedupe set is session scoped: a new TUN starts with
//! an empty set, exactly like `connLogSeen.reset()` in `StartFull`.

use std::sync::Arc;

use diting_gate_core::admit::{
    ACTION_BLOCK_ENCRYPTED_DNS, ACTION_BLOCK_QUIC, ACTION_BLOCK_UID, ACTION_HANDLE_DNS,
    ACTION_INTERCEPT, ACTION_RELAY, MODE_FULL_TCP, MODE_FULL_UDP, MODE_MITM_TCP,
};
use diting_gate_core::{admit, FlowInput};
use diting_telemetry_core::LogItem;

use crate::attribution::{PROTOCOL_TCP, PROTOCOL_UDP};
use crate::engine::{now_ms, Engine};
use crate::netstack::TcpKey;

/// What the session does with one admitted flow.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlowAction {
    /// Answer it from the DNS pipeline (`handleDNSOverUdp` / `handleDNSOverTCP`).
    HandleDns,
    /// Relay it out through the engine's outbound transport.
    Relay,
    /// MITM is active and the flow is `:80`/`:443` for a selected app: peek, then decrypt or passthrough.
    Intercept,
    /// Blocked by the gate; the reason is already logged.
    Blocked,
}

/// One flow's attribution, resolved once when the flow opens.
#[derive(Clone, Debug, Default)]
pub struct FlowContext {
    pub uid: i32,
    pub app: String,
}

/// Resolves the UID and package of one flow through the Kotlin callbacks.
pub fn context_for(
    engine: &Engine,
    protocol: i32,
    app: smoltcp::wire::IpEndpoint,
    server: smoltcp::wire::IpEndpoint,
) -> FlowContext {
    let uid = engine.flow_uid(protocol, app, server);
    FlowContext {
        app: engine.app_name(uid),
        uid,
    }
}

/// Applies the gate and logs the connection, exactly like the Go flow handlers did.
///
/// `tcp` selects `gateModeFullTCP` / `gateModeFullUDP`. The app allowlist has no Kotlin caller yet
/// (migration plan §4.3), so it is passed as "allowed" — the same value Go produced with an empty
/// allowlist. [`admit_mitm_flow`] is the third mode, used when MITM is running.
pub fn admit_flow(
    engine: &Arc<Engine>,
    tcp: bool,
    key: &TcpKey,
    context: &FlowContext,
) -> FlowAction {
    let mode = if tcp { MODE_FULL_TCP } else { MODE_FULL_UDP };
    // Go's full-tunnel UDP handler passed `quicUIDSelected` from the live MITM filter, which is
    // what makes `setFilterHttp3` drop QUIC only for the inspected apps. Without it every app's
    // UDP :443 is relayed, so HTTP/3 sites never fall back to TCP and MITM cannot see them.
    let selected = !tcp && mitm_uid_selected(engine, context.uid);
    decide(engine, mode, key, context, selected)
}

/// The MITM gate (`mitm_handler.go`'s `gateAdmitFlow(gateModeMitmTCP, …)`).
///
/// `mitm_uid_allowed` is `filter.HasAllowedUIDs() && uid != UIDUnknown && filter.IsUIDAllowed(uid)`;
/// an empty allow list therefore relays everything, which is what Go did before the UI pushed one.
pub fn admit_mitm_flow(engine: &Arc<Engine>, key: &TcpKey, context: &FlowContext) -> FlowAction {
    let selected = mitm_uid_selected(engine, context.uid);
    decide(engine, MODE_MITM_TCP, key, context, selected)
}

/// The per-UID MITM allow list, read from the live session's filter.
fn mitm_uid_selected(engine: &Engine, uid: i32) -> bool {
    let Some(mitm) = engine.mitm_state().session() else {
        return false;
    };
    uid >= 0 && mitm.filter().is_uid_allowed(i64::from(uid))
}

fn decide(
    engine: &Arc<Engine>,
    mode: u8,
    key: &TcpKey,
    context: &FlowContext,
    mitm_uid_allowed: bool,
) -> FlowAction {
    let port = key.local.port;
    let input = FlowInput {
        uid_blocked: engine.is_uid_blocked(context.uid),
        app_allowlist_allowed: true,
        encrypted_dns_blocked: engine.block_encrypted_dns() && port == PORT_DOT,
        quic_drop: engine.filter_http3(),
        quic_uid_selected: mitm_uid_allowed,
        mitm_uid_allowed,
        port,
        ip: &crate::netstack::address_bytes(key.local.addr),
    };
    let decision = admit(mode, &input);
    let protocol = if mode == MODE_FULL_UDP {
        PROTOCOL_UDP
    } else {
        PROTOCOL_TCP
    };

    record_flow(engine, protocol, key, context, port, decision.action);

    if decision.log_connection {
        log_connection(engine, protocol, key, context);
    }

    match decision.action {
        ACTION_HANDLE_DNS => FlowAction::HandleDns,
        ACTION_RELAY => FlowAction::Relay,
        ACTION_INTERCEPT => FlowAction::Intercept,
        ACTION_BLOCK_UID => {
            log_blocked(engine, protocol, key, context, "uid_blocked");
            FlowAction::Blocked
        }
        ACTION_BLOCK_ENCRYPTED_DNS => {
            log_blocked(engine, protocol, key, context, "blocked_encrypted_dns");
            FlowAction::Blocked
        }
        ACTION_BLOCK_QUIC => {
            log_blocked(engine, protocol, key, context, "quic_forced_tcp");
            FlowAction::Blocked
        }
        _ => FlowAction::Blocked,
    }
}

/// `encryptedDNSPort`.
pub const PORT_DOT: u16 = 853;
/// `PORT_DNS`.
pub const PORT_DNS: u16 = 53;

/// Records the flow into the engine's live connection table (U 实时连接视图). Bytes accrue later
/// through the traffic path; here we pin the identity, owner, destination and initial status.
fn record_flow(
    engine: &Arc<Engine>,
    protocol: i32,
    key: &TcpKey,
    context: &FlowContext,
    port: u16,
    action: u8,
) {
    let blocked = matches!(
        action,
        ACTION_BLOCK_UID | ACTION_BLOCK_ENCRYPTED_DNS | ACTION_BLOCK_QUIC
    );
    let flow_key = diting_flow_core::FlowKey {
        protocol: if protocol == PROTOCOL_UDP { "udp" } else { "tcp" }.to_string(),
        src_ip: crate::netstack::address_text(key.remote.addr),
        src_port: key.remote.port,
        dst_ip: crate::netstack::address_text(key.local.addr),
        dst_port: port,
        uid: context.uid,
    };
    let status = if blocked {
        diting_flow_core::FlowStatus::Failed
    } else {
        diting_flow_core::FlowStatus::Active
    };
    engine.record_flow(flow_key, &context.app, "", status);
}

fn log_connection(engine: &Engine, protocol: i32, key: &TcpKey, context: &FlowContext) {
    connection_row(engine, protocol, key, context, false, "connection");
}

fn log_blocked(engine: &Engine, protocol: i32, key: &TcpKey, context: &FlowContext, reason: &str) {
    connection_row(
        engine,
        protocol,
        key,
        context,
        true,
        &format!("firewall:{reason}"),
    );
}

/// `logConnection` / `logBlockedConnection`: one deduplicated row per `app|dest|port|proto`.
fn connection_row(
    engine: &Engine,
    protocol: i32,
    key: &TcpKey,
    context: &FlowContext,
    blocked: bool,
    marker: &str,
) {
    if !engine.logs().has_sink() {
        return;
    }
    let dest = crate::netstack::address_text(key.local.addr);
    let app = engine.display_name(context.uid);
    let reason = marker.strip_prefix("firewall:").unwrap_or("");
    let prefix = if blocked { "blk|" } else { "" };
    if engine.connlog().mark(
        prefix,
        &app,
        &dest,
        i32::from(key.local.port),
        protocol,
        reason,
    ) {
        return;
    }
    let proto = if protocol == PROTOCOL_UDP {
        "UDP"
    } else {
        "TCP"
    };
    engine.logs().push(LogItem {
        domain: format!("{proto} {dest}:{}", key.local.port),
        blocked,
        query_type: 0,
        response_time_ms: 0,
        app_name: app,
        resolved_ips: dest,
        blocked_by: marker.to_string(),
        error_message: String::new(),
        cached: false,
        timestamp_ms: now_ms(),
        ttl: 0,
    });
}
