//! The data plane's counters and the two JSON documents it produces.
//!
//! * [`traffic_json`] — the `TrafficCallback.onTrafficStatsTick` payload,
//!   `[{"uid":10086,"tx":123,"rx":456}]`, byte-identical to Go's `json.Marshal(uidDeltaJson)`.
//! * [`TunnelCounters::document`] — the extra `"tun"` object `getStats` carries while the TUN runs.
//!   The three fields `EngineStats.kt` reads (`total`, `blocked`, `dropped_logs`) are untouched; a
//!   UI that ignores unknown keys keeps working, and a support log finally says whether the queue
//!   dropped packets or the writer retried.
//!
//! The stack's own counters ([`crate::netstack::Stats`]) are snapshotted by the session on stop, so
//! this module never borrows the stack.

use std::sync::atomic::{AtomicU64, Ordering};

use diting_telemetry_core::Delta;

/// The session's counters, shared by the reader, the writer, the stack thread and the handlers.
#[derive(Debug, Default)]
pub struct TunnelCounters {
    pub ingress_dropped: AtomicU64,
    pub egress_dropped: AtomicU64,
    pub write_retries: AtomicU64,
    pub write_failures: AtomicU64,
    pub tcp_flows: AtomicU64,
    pub udp_datagrams: AtomicU64,
    pub blocked_flows: AtomicU64,
    /// A relay dial failed, or the proxy has no datagram mode for this flow.
    pub relay_unavailable: AtomicU64,
    pub malformed: AtomicU64,
    /// A response larger than the client's send buffer / a handler that fell behind.
    pub short_writes: AtomicU64,
    /// `udp_send` could not queue an answer (port unbound or buffer full).
    pub udp_replies_dropped: AtomicU64,
}

impl TunnelCounters {
    pub fn count(counter: &AtomicU64, value: u64) {
        if value > 0 {
            counter.fetch_add(value, Ordering::Relaxed);
        }
    }

    pub fn get(counter: &AtomicU64) -> u64 {
        counter.load(Ordering::Relaxed)
    }

    /// The `"tun"` document, folded into `getStats`.
    pub fn document(&self, stack: crate::netstack::Stats) -> serde_json::Value {
        serde_json::json!({
            "packetsIn": stack.packets_in,
            "packetsOut": stack.packets_out,
            "bytesIn": stack.bytes_in,
            "bytesOut": stack.bytes_out,
            "malformed": stack.malformed + TunnelCounters::get(&self.malformed),
            "tcpFlows": TunnelCounters::get(&self.tcp_flows),
            "udpDatagrams": TunnelCounters::get(&self.udp_datagrams),
            "blockedFlows": TunnelCounters::get(&self.blocked_flows),
            "relayUnavailable": TunnelCounters::get(&self.relay_unavailable),
            "ingressDropped": TunnelCounters::get(&self.ingress_dropped),
            "egressDropped": TunnelCounters::get(&self.egress_dropped),
            "writeRetries": TunnelCounters::get(&self.write_retries),
            "writeFailures": TunnelCounters::get(&self.write_failures),
            "shortWrites": TunnelCounters::get(&self.short_writes),
            "udpRepliesDropped": TunnelCounters::get(&self.udp_replies_dropped),
            "stackTcpAccepted": stack.tcp_accepted,
            "stackTcpClosed": stack.tcp_closed,
            "stackTcpRejected": stack.tcp_rejected,
            "stackTcpExpired": stack.tcp_expired,
            "stackUdpBound": stack.udp_bound,
            "stackUdpRejected": stack.udp_rejected,
        })
    }
}

/// `TrafficCallback.onTrafficStatsTick`: the per-UID deltas since the last tick.
///
/// The field names are read by `TrafficIngest`, so they cannot change: `uid`, `tx`, `rx`.
pub fn traffic_json(deltas: &[Delta]) -> String {
    let rows: Vec<serde_json::Value> = deltas
        .iter()
        .map(|delta| {
            serde_json::json!({
                "uid": delta.uid,
                "tx": delta.tx,
                "rx": delta.rx,
            })
        })
        .collect();
    serde_json::Value::Array(rows).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_traffic_tick_is_the_array_the_kotlin_ingest_parses() {
        let json = traffic_json(&[
            Delta {
                uid: 10086,
                tx: 12,
                rx: 34,
            },
            Delta {
                uid: 1000,
                tx: 0,
                rx: 8,
            },
        ]);
        assert_eq!(
            json,
            r#"[{"rx":34,"tx":12,"uid":10086},{"rx":8,"tx":0,"uid":1000}]"#
        );
        let parsed: serde_json::Value = serde_json::from_str(&json).expect("json");
        assert_eq!(parsed[0]["uid"], serde_json::json!(10086));
    }

    #[test]
    fn no_traffic_is_an_empty_array_not_null() {
        assert_eq!(traffic_json(&[]), "[]");
    }

    #[test]
    fn the_tun_document_carries_the_queue_and_stack_numbers() {
        let counters = TunnelCounters::default();
        counters.ingress_dropped.fetch_add(2, Ordering::Relaxed);
        let document = counters.document(crate::netstack::Stats {
            packets_in: 7,
            tcp_accepted: 3,
            ..Default::default()
        });
        assert_eq!(document["packetsIn"], serde_json::json!(7));
        assert_eq!(document["ingressDropped"], serde_json::json!(2));
        assert_eq!(document["stackTcpAccepted"], serde_json::json!(3));
    }
}
