use std::sync::{Arc, Mutex};

use tokio::sync::mpsc;
use tokio::task::JoinSet;

use crate::engine::Engine;
use crate::tunnel::dnsflow::Inbound;
use crate::tunnel::gate::FlowContext;

pub(super) struct Flow {
    pub(super) tx: mpsc::Sender<Inbound>,
    pub(super) context: FlowContext,
}

pub(super) fn spawn_flow(
    engine: &Arc<Engine>,
    flow_tasks: &Arc<Mutex<JoinSet<()>>>,
    future: impl std::future::Future<Output = ()> + Send + 'static,
) {
    flow_tasks
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .spawn_on(future, engine.runtime().handle());
}

pub(super) fn reap_flows(flow_tasks: &Arc<Mutex<JoinSet<()>>>) {
    let mut tasks = flow_tasks.lock().unwrap_or_else(|error| error.into_inner());
    while tasks.try_join_next().is_some() {}
}
