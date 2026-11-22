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
        let clients = self.clients.clone();
        tokio::spawn(async move {
            let _ = clients.resolve_reverse(ip).await;
        });
        StageResult::Continue
    }
}
