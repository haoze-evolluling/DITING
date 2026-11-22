use std::sync::Arc;

use diting_connlog_core::ConnLogDedup;
use diting_flow_core::{FlowEvent, FlowKey, FlowStatus, OwnedSnapshot};
use smoltcp::wire::IpEndpoint;

use super::{now_ms, Engine};

impl Engine {
    pub fn attribution(&self) -> &crate::attribution::Attribution {
        &self.attribution
    }

    pub fn mitm_state(&self) -> &Arc<crate::mitm::MitmState> {
        &self.mitm
    }

    pub fn connlog(&self) -> &ConnLogDedup {
        &self.connlog
    }

    pub fn record_flow(&self, key: FlowKey, app: &str, domain: &str, status: FlowStatus) {
        // 与仓库其它地方一致：中毒的锁照常使用内部值，否则这条连接记录会被静默丢掉。
        self.flows
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .record(FlowEvent {
                key,
                domain: domain.to_string(),
                package: app.to_string(),
                up_delta: 0,
                down_delta: 0,
                status,
                at_ms: now_ms(),
            });
    }

    pub fn flow_snapshot_json(&self, since_seq: u64, limit: usize) -> String {
        let Ok(table) = self.flows.lock() else {
            return concat!(
                "{\"baseSeq\":0,\"nextSeq\":0,\"total\":0,",
                "\"truncated\":false,\"sessions\":[]}"
            )
            .to_string();
        };
        let (next_seq, items) = table.collect_since(since_seq);
        drop(table);
        OwnedSnapshot::from_collected(since_seq, next_seq, items, limit).to_json()
    }

    pub fn flow_uid(&self, protocol: i32, app: IpEndpoint, server: IpEndpoint) -> i32 {
        self.attribution
            .uid_for(protocol, app, server, crate::resolver::now_ns())
    }

    pub fn app_name(&self, uid: i32) -> String {
        self.attribution.package_for(uid, crate::resolver::now_ns())
    }

    pub fn display_name(&self, uid: i32) -> String {
        self.attribution
            .display_name(uid, crate::resolver::now_ns())
    }
}
