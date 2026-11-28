use std::sync::Arc;

use tokio::sync::{mpsc, watch};
use tokio::task::JoinSet;

use crate::engine::Engine;
use crate::tunnel::dnsflow::Inbound;
use crate::tunnel::gate::FlowContext;

pub(super) struct Flow {
    pub(super) tx: mpsc::Sender<Inbound>,
    pub(super) context: FlowContext,
    /// 网络切换中止流时通知 relay 任务退出并关闭上游 socket；DNS/拦截流没有。
    pub(super) cancel: Option<watch::Sender<bool>>,
}

/// 流任务表由栈线程独占：它只被栈线程 spawn 和回收，
/// 不需要为了关闭期共享而在每轮循环/每条连接上抢一把 `Mutex`。
pub(super) fn spawn_flow(
    engine: &Arc<Engine>,
    flow_tasks: &mut JoinSet<()>,
    future: impl std::future::Future<Output = ()> + Send + 'static,
) {
    flow_tasks.spawn_on(future, engine.runtime().handle());
}

pub(super) fn reap_flows(flow_tasks: &mut JoinSet<()>) {
    while flow_tasks.try_join_next().is_some() {}
}
