mod config;
mod filters;
mod flows;
mod full;
mod report;
mod resolve;
mod runtime;

use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{SystemTime, UNIX_EPOCH};

use diting_connlog_core::ConnLogDedup;
use diting_dns_core::block::{BlockConfig, DynamicBlocks};
use diting_flow_core::FlowTable;
use diting_gate_core::BlockedUids;
use diting_telemetry_core::TrafficTracker;
use tokio::runtime::Runtime;

use crate::attribution::Attribution;
use crate::cache::DnsCache;
use crate::config::DnsConfig;
use crate::connection_limit::ConnectionLimiter;
use crate::dns::LogRow;
use crate::logs::{BootstrapSink, Logs};
use crate::outbound::{Outbound, StatusDispatcher, StatusSink};
use crate::policy::{Policy, Rewrites};
use crate::protect::ProtectorHandle;
use crate::resolver::{Bootstrap, Resolver, ResolverDeps, StatsStore, SystemDns, UpstreamTrust};
use crate::standalone::Standalone;
use crate::tunnel::Session;

pub use resolve::resolve_domain_error_json;

pub const DEFAULT_TUN_MTU: usize = 1400;

pub trait TrafficSink: Send + Sync + 'static {
    fn tick(&self, payload: &[u8]);
}

struct EngineRuntime(Option<Runtime>);

impl EngineRuntime {
    fn new() -> Self {
        let runtime = tokio::runtime::Builder::new_multi_thread()
            .worker_threads(2)
            .thread_name("diting-engine")
            .enable_all()
            .build()
            .expect("the engine runtime must start");
        Self(Some(runtime))
    }

    fn handle(&self) -> &Runtime {
        self.0.as_ref().expect("the engine runtime is alive")
    }
}

impl Drop for EngineRuntime {
    fn drop(&mut self) {
        if let Some(runtime) = self.0.take() {
            runtime.shutdown_background();
        }
    }
}

pub struct Engine {
    started_at_ms: i64,
    runtime: EngineRuntime,
    cache: DnsCache,
    policy: Policy,
    rewrites: Rewrites,
    dynamic_blocks: DynamicBlocks,
    filter_dns: AtomicBool,
    block_ipv6: AtomicBool,
    blocked_qtypes: RwLock<Vec<u16>>,
    rebinding_protection: AtomicBool,
    dns64: RwLock<Option<Arc<diting_dns64_core::Engine>>>,
    rate_limit: RwLock<Option<diting_ratelimit_core::RateLimiter>>,
    connection_limit: RwLock<Option<Arc<ConnectionLimiter>>>,
    block_response: AtomicU32,
    pause_until_ms: AtomicI64,
    allowlist_only: AtomicBool,
    dynamic_config: RwLock<BlockConfig>,
    config: RwLock<Option<DnsConfig>>,
    resolver: RwLock<Arc<Resolver>>,
    stats: Arc<StatsStore>,
    bootstrap: Arc<Bootstrap>,
    system_dns: SystemDns,
    negative: crate::dns::negative::NegativeCache,
    trust: RwLock<Arc<UpstreamTrust>>,
    protector: ProtectorHandle,
    outbound: Arc<RwLock<Outbound>>,
    outbound_status: Arc<StatusDispatcher>,
    logs: Arc<Logs>,
    flights: Mutex<std::collections::HashMap<Vec<u8>, crate::dns::flight::Flight>>,
    total_queries: AtomicU64,
    blocked_queries: AtomicU64,
    server: Mutex<Option<Standalone>>,
    running: AtomicBool,
    attribution: Attribution,
    connlog: ConnLogDedup,
    flows: Mutex<FlowTable>,
    blocked_uids: RwLock<Arc<BlockedUids>>,
    quic_drop: AtomicBool,
    block_encrypted_dns: AtomicBool,
    traffic: Arc<TrafficTracker>,
    traffic_sink: RwLock<Option<Arc<dyn TrafficSink>>>,
    tick_interval_ms: AtomicU64,
    full: Mutex<Option<Session>>,
    ticker: Mutex<Option<Arc<AtomicBool>>>,
    mitm: Arc<crate::mitm::MitmState>,
}

impl Engine {
    pub fn new() -> Self {
        let logs = Arc::new(Logs::new());
        let sink: Arc<dyn BootstrapSink> = logs.clone();
        let protector = ProtectorHandle::new();
        let outbound_status = Arc::new(StatusDispatcher::default());
        let bootstrap = Arc::new(Bootstrap::with_protector(sink, protector.clone()));
        let trust = Arc::new(UpstreamTrust::platform());
        let stats = Arc::new(StatsStore::default());
        let system_dns = SystemDns::default();
        let outbound = Arc::new(RwLock::new(Outbound::new(
            crate::outbound::Config::default(),
            protector.clone(),
            Arc::clone(&outbound_status),
        )));
        Self {
            started_at_ms: now_ms(),
            runtime: EngineRuntime::new(),
            cache: DnsCache::new(),
            policy: Policy::default(),
            rewrites: Rewrites::default(),
            dynamic_blocks: DynamicBlocks::new(),
            filter_dns: AtomicBool::new(false),
            block_ipv6: AtomicBool::new(false),
            blocked_qtypes: RwLock::new(Vec::new()),
            rebinding_protection: AtomicBool::new(false),
            dns64: RwLock::new(None),
            rate_limit: RwLock::new(None),
            connection_limit: RwLock::new(None),
            block_response: AtomicU32::new(0),
            pause_until_ms: AtomicI64::new(0),
            allowlist_only: AtomicBool::new(false),
            dynamic_config: RwLock::new(BlockConfig {
                enabled: false,
                request_threshold: 0,
                window_ns: 0,
                nx_domain_ns: 0,
            }),
            config: RwLock::new(None),
            resolver: RwLock::new(Arc::new(Resolver::empty(ResolverDeps {
                trust: Arc::clone(&trust),
                bootstrap: Arc::clone(&bootstrap),
                stats: Arc::clone(&stats),
                protector: protector.clone(),
                outbound: Some(Arc::clone(&outbound)),
                system_dns: system_dns.clone(),
            }))),
            stats,
            bootstrap,
            system_dns,
            negative: crate::dns::negative::NegativeCache::default(),
            protector: protector.clone(),
            outbound,
            outbound_status,
            trust: RwLock::new(trust),
            logs,
            flights: Mutex::new(std::collections::HashMap::new()),
            total_queries: AtomicU64::new(0),
            blocked_queries: AtomicU64::new(0),
            server: Mutex::new(None),
            running: AtomicBool::new(false),
            attribution: Attribution::new(),
            connlog: ConnLogDedup::new(),
            flows: Mutex::new(FlowTable::new(4096)),
            blocked_uids: RwLock::new(Arc::new(BlockedUids::parse_csv(""))),
            quic_drop: AtomicBool::new(false),
            block_encrypted_dns: AtomicBool::new(false),
            traffic: Arc::new(TrafficTracker::new()),
            traffic_sink: RwLock::new(None),
            tick_interval_ms: AtomicU64::new(
                diting_telemetry_core::traffic::DEFAULT_TICK_INTERVAL_MS.max(100) as u64,
            ),
            full: Mutex::new(None),
            ticker: Mutex::new(None),
            mitm: Arc::new(crate::mitm::MitmState::new()),
        }
    }

    pub fn cache(&self) -> &DnsCache {
        &self.cache
    }

    pub fn policy(&self) -> &Policy {
        &self.policy
    }

    pub fn rewrites(&self) -> &Rewrites {
        &self.rewrites
    }

    pub fn logs(&self) -> &Logs {
        &self.logs
    }

    pub fn upstream_trust(&self) -> Arc<UpstreamTrust> {
        self.trust
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn protector(&self) -> ProtectorHandle {
        self.protector.clone()
    }

    pub fn outbound(&self) -> Outbound {
        self.outbound
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn configure_outbound_proxy(&self, payload: &str) -> String {
        match crate::outbound::Config::parse(payload) {
            Ok(config) => {
                let outbound = Outbound::new(
                    config,
                    self.protector.clone(),
                    Arc::clone(&self.outbound_status),
                );
                *self
                    .outbound
                    .write()
                    .unwrap_or_else(|error| error.into_inner()) = outbound;
                String::new()
            }
            Err(error) => error,
        }
    }

    pub fn set_outbound_status_sink(&self, sink: Option<Arc<dyn StatusSink>>) {
        self.outbound_status.set(sink);
    }

    pub fn set_upstream_trust(&self, trust: Arc<UpstreamTrust>) {
        *self
            .trust
            .write()
            .unwrap_or_else(|error| error.into_inner()) = trust;
    }

    pub fn flights(
        &self,
    ) -> &Mutex<std::collections::HashMap<Vec<u8>, crate::dns::flight::Flight>> {
        &self.flights
    }

    pub fn resolver(&self) -> Arc<Resolver> {
        self.resolver
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn runtime(&self) -> &Runtime {
        self.runtime.handle()
    }

    pub fn spawn<F>(&self, future: F)
    where
        F: std::future::Future<Output = ()> + Send + 'static,
    {
        self.runtime.handle().spawn(future);
    }

    pub fn spawn_task<F>(&self, future: F) -> tokio::task::JoinHandle<()>
    where
        F: std::future::Future<Output = ()> + Send + 'static,
    {
        self.runtime.handle().spawn(future)
    }

    pub fn block_on<F: std::future::Future>(&self, future: F) -> F::Output {
        self.runtime.handle().block_on(future)
    }

    /// 构造一行 DNS 日志。
    ///
    /// 参数是闭包而不是 `LogRow`：DNS 每查询至少要造 2~3 个 `String`，而 `Logs::push` 的第一件事
    /// 就是「没有 sink 直接丢」。没有 sink 时连行对象都不构造。
    pub fn log_row(&self, build: impl FnOnce() -> LogRow) {
        if !self.logs.wants() {
            return;
        }
        self.logs.push(build().build(now_ms()));
    }

    pub fn log_error(&self, message: &str) {
        if message.is_empty() {
            return;
        }
        let row: diting_telemetry_core::LogItem = LogRow::error_row(message, now_ms());
        self.logs.push(row);
    }
}

impl Default for Engine {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        self.stop_full();
        self.stop_standalone();
    }
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}
