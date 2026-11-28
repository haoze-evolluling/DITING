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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FlowAction {
    HandleDns,
    Relay,
    Intercept,
    Blocked,
}

#[derive(Clone, Debug, Default)]
pub struct FlowContext {
    pub uid: i32,
    pub app: String,
}

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

pub fn admit_flow(
    engine: &Arc<Engine>,
    tcp: bool,
    key: &TcpKey,
    context: &FlowContext,
) -> FlowAction {
    let mode = if tcp { MODE_FULL_TCP } else { MODE_FULL_UDP };
    let selected = !tcp && mitm_uid_selected(engine, context.uid);
    decide(engine, mode, key, context, selected)
}

pub fn admit_mitm_flow(engine: &Arc<Engine>, key: &TcpKey, context: &FlowContext) -> FlowAction {
    let selected = mitm_uid_selected(engine, context.uid);
    decide(engine, MODE_MITM_TCP, key, context, selected)
}

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
    // 每条新连接都会走到这里，地址写进栈缓冲，避免为 4/16 字节做一次堆分配。
    let mut ip = [0u8; 16];
    let ip_len = crate::netstack::address_bytes_into(key.local.addr, &mut ip);
    let input = FlowInput {
        uid_blocked: engine.is_uid_blocked(context.uid),
        app_allowlist_allowed: true,
        encrypted_dns_blocked: engine.block_encrypted_dns() && port == PORT_DOT,
        quic_drop: engine.filter_http3(),
        quic_uid_selected: mitm_uid_allowed,
        mitm_uid_allowed,
        port,
        ip: &ip[..ip_len],
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

pub const PORT_DOT: u16 = 853;
pub const PORT_DNS: u16 = 53;

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
        protocol: if protocol == PROTOCOL_UDP {
            diting_flow_core::FlowProtocol::Udp
        } else {
            diting_flow_core::FlowProtocol::Tcp
        },
        src_ip: crate::netstack::flow_addr(key.remote.addr),
        src_port: key.remote.port,
        dst_ip: crate::netstack::flow_addr(key.local.addr),
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
        ..LogItem::default()
    });
}
