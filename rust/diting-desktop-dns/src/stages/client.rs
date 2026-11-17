//! Client identity and group tagging.
//!
//! The group must be written before the cache stage: the cache key carries the group, and a key
//! written before grouping would put every client in the default partition. Reverse DNS fills the
//! display name, but only from cache on the hot path — the lookup itself runs in the background so
//! a slow PTR server cannot delay every query.

use std::sync::Arc;

use async_trait::async_trait;

use diting_desktop_core::clients::ClientDirectory;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};

pub struct ClientStage {
    clients: Arc<ClientDirectory>,
}

impl ClientStage {
    pub fn new(clients: Arc<ClientDirectory>) -> Self {
        Self { clients }
    }
}

#[async_trait]
impl Stage for ClientStage {
    fn name(&self) -> &'static str {
        "client"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let Some(ip) = ctx.client.map(|address| address.ip()) else {
            return StageResult::Continue;
        };
        let name = self.clients.identify(ip);
        if !name.is_empty() {
            ctx.client_name = name.clone();
            ctx.set("client_name", name);
        }
        let group = self.clients.group(ip);
        ctx.group = group.clone();
        ctx.set("client_group", group);
        // Warm the reverse name without blocking this query. `resolve_reverse` enforces the
        // configured TTL/negative cache and single-flight, so repeated spawns are cheap.
        let clients = self.clients.clone();
        tokio::spawn(async move {
            let _ = clients.resolve_reverse(ip).await;
        });
        StageResult::Continue
    }
}
