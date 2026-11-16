//! The data plane's counters and the two documents it produces.
//!
//! * [`traffic_payload`] — the `TrafficCallback.onTrafficStatsTick` payload, one packed `byte[]`
//!   with `(uid, tx, rx, package)` rows in the log kernel's input layout.
//! * [`TunnelCounters::document`] — the extra `"tun"` object `getStats` carries while the TUN runs.
//!   The three fields `EngineStats.kt` reads (`total`, `blocked`, `dropped_logs`) are untouched; a
//!   UI that ignores unknown keys keeps working, and a support log finally says whether the queue
//!   dropped packets or the writer retried.
//!
//! The stack's own counters ([`crate::netstack::Stats`]) are snapshotted by the session on stop, so
//! this module never borrows the stack.

use std::sync::atomic::{AtomicU64, Ordering};

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

/// One per-UID delta in the tick payload, with the package name already resolved.
pub type TrafficRow = (i32, i64, i64, String);

/// `TrafficCallback.onTrafficStatsTick`: `u32 count | (i32 uid, i64 tx, i64 rx, string package)`.
///
/// This is exactly the row section `diting_log_core::api::traffic_on_tick` decodes. Kotlin only
/// prepends the date string and forwards the same buffer, so the tick is encoded once here instead
/// of being serialized to JSON, parsed back into `JSONArray` and packed again on the JVM side.
pub fn traffic_payload(rows: &[TrafficRow]) -> Vec<u8> {
    let strings: usize = rows.iter().map(|row| row.3.len()).sum();
    let mut out = Vec::with_capacity(4 + rows.len() * 24 + strings + rows.len() * 4);
    out.extend_from_slice(&(rows.len() as u32).to_be_bytes());
    for (uid, tx, rx, package) in rows {
        out.extend_from_slice(&uid.to_be_bytes());
        out.extend_from_slice(&tx.to_be_bytes());
        out.extend_from_slice(&rx.to_be_bytes());
        out.extend_from_slice(&(package.len() as u32).to_be_bytes());
        out.extend_from_slice(package.as_bytes());
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_traffic_tick_is_the_log_kernel_input_layout() {
        let payload = traffic_payload(&[
            (10086, 12, 34, "com.example".to_string()),
            (1000, 0, 8, String::new()),
        ]);
        assert_eq!(
            u32::from_be_bytes(payload[0..4].try_into().unwrap()),
            2,
            "the count leads the payload"
        );
        assert_eq!(
            i32::from_be_bytes(payload[4..8].try_into().unwrap()),
            10086,
            "the first uid"
        );
        assert_eq!(i64::from_be_bytes(payload[8..16].try_into().unwrap()), 12);
        assert_eq!(i64::from_be_bytes(payload[16..24].try_into().unwrap()), 34);
        let length = u32::from_be_bytes(payload[24..28].try_into().unwrap()) as usize;
        assert_eq!(&payload[28..28 + length], b"com.example");
    }

    #[test]
    fn no_traffic_is_a_zero_count_not_null() {
        assert_eq!(traffic_payload(&[]), vec![0, 0, 0, 0]);
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
