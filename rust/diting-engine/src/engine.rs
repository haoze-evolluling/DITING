use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use diting_connlog_core::ConnLogDedup;
use diting_dns_cache_core::policy::Config as CacheConfig;
use diting_dns_core::block::{BlockConfig, DynamicBlocks};
use diting_dns_core::message::{TYPE_A, TYPE_AAAA};
use diting_dns_core::reply::REWRITE_ANSWER_TTL;
use diting_dns_wire::format_ipv4;
use diting_flow_core::{FlowEvent, FlowKey, FlowStatus, FlowTable};
use diting_gate_core::BlockedUids;
use diting_telemetry_core::{LogItem, TrafficTracker};
use smoltcp::wire::IpEndpoint;
use tokio::runtime::Runtime;

use crate::attribution::Attribution;
use crate::cache::DnsCache;
use crate::config::DnsConfig;
use crate::connection_limit::{BucketKind, Config as ConnectionLimitConfig, ConnectionLimiter};
use crate::dns::LogRow;
use crate::error::{EngineError, EngineResult};
use crate::logs::{BootstrapSink, EventSink, Logs};
use crate::outbound::{Outbound, StatusDispatcher, StatusSink};
use crate::policy::{rewrites_from_json, Policy, Rewrites};
use crate::protect::ProtectorHandle;
use crate::resolver::{Bootstrap, Resolver, ResolverDeps, StatsStore, UpstreamTrust};
use crate::standalone::Standalone;
use crate::tunnel::{PacketLink, Session, TunFd};

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
            }))),
            stats,
            bootstrap,
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


    pub fn apply_dns_config(&self, payload: &str) -> EngineResult<()> {
        let config = DnsConfig::from_json(payload)?;

        self.cache.apply_policy(config.cache.clone());
        self.publish_resolver(&config);
        self.block_response
            .store(config.block_response, Ordering::Release);
        *self
            .blocked_qtypes
            .write()
            .unwrap_or_else(|error| error.into_inner()) = config.privacy.blocked_qtypes.clone();
        self.rebinding_protection
            .store(config.privacy.rebinding_protection, Ordering::Release);
        if let Err(error) = self.set_dns64(config.dns64, &[]) {
            self.log_error(&error);
        }
        self.set_rate_limit(&config.rate_limit);
        self.set_connection_rate_limit(config.connection_rate_limit);
        *self
            .dynamic_config
            .write()
            .unwrap_or_else(|error| error.into_inner()) = config.dynamic_response;
        self.dynamic_blocks.reset();
        *self
            .config
            .write()
            .unwrap_or_else(|error| error.into_inner()) = Some(config);
        Ok(())
    }

    fn publish_resolver(&self, config: &DnsConfig) {
        let deps = ResolverDeps {
            trust: self.upstream_trust(),
            bootstrap: Arc::clone(&self.bootstrap),
            stats: Arc::clone(&self.stats),
            protector: self.protector.clone(),
            outbound: Some(Arc::clone(&self.outbound)),
        };
        let resolver = Arc::new(Resolver::configured(config, deps));
        for reason in resolver.skipped() {
            self.log_error(reason);
        }
        let previous = std::mem::replace(
            &mut *self
                .resolver
                .write()
                .unwrap_or_else(|error| error.into_inner()),
            resolver,
        );
        previous.shutdown();
    }

    pub fn apply_rule_snapshot(&self, payload: &str) -> String {
        self.policy.apply(payload)
    }

    pub fn set_rewrite_rules(&self, payload: &str) {
        if payload.is_empty() {
            return;
        }
        match rewrites_from_json(payload) {
            Ok(entries) => self
                .rewrites
                .publish(diting_dns_core::RewriteTable::build(&entries)),
            Err(error) => self.log_error(&error),
        }
    }

    pub fn set_filter_dns(&self, enabled: bool) {
        self.filter_dns.store(enabled, Ordering::Release);
    }

    pub fn filter_dns(&self) -> bool {
        self.filter_dns.load(Ordering::Acquire)
    }

    pub fn set_block_ipv6(&self, enabled: bool) {
        self.block_ipv6.store(enabled, Ordering::Release);
    }

    pub fn block_ipv6(&self) -> bool {
        self.block_ipv6.load(Ordering::Acquire)
    }

    pub fn records_blocked(&self, qtype: u16) -> bool {
        self.blocked_qtypes
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .contains(&qtype)
    }

    pub fn rebinding_protection(&self) -> bool {
        self.rebinding_protection.load(Ordering::Acquire)
    }

    pub fn set_dns64(&self, enabled: bool, prefixes: &[String]) -> Result<(), String> {
        let engine = if enabled {
            Some(Arc::new(
                diting_dns64_core::Engine::new(true, prefixes)
                    .map_err(|error| format!("dns64 prefix rejected: {error:?}"))?,
            ))
        } else {
            None
        };
        *self
            .dns64
            .write()
            .unwrap_or_else(|error| error.into_inner()) = engine;
        Ok(())
    }

    pub fn dns64(&self) -> Option<Arc<diting_dns64_core::Engine>> {
        self.dns64
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn set_rate_limit(&self, config: &diting_ratelimit_core::Config) {
        let limiter = if config.enabled {
            Some(diting_ratelimit_core::RateLimiter::new(config))
        } else {
            None
        };
        *self
            .rate_limit
            .write()
            .unwrap_or_else(|error| error.into_inner()) = limiter;
    }

    pub fn allow_client(&self, address: Option<&diting_ratelimit_core::Addr>, now_ns: i64) -> bool {
        match self
            .rate_limit
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
        {
            None => true,
            Some(limiter) => {
                limiter.allow(address, now_ns, diting_ratelimit_core::DEFAULT_MAX_BUCKETS)
            }
        }
    }

    pub fn set_connection_rate_limit(&self, config: ConnectionLimitConfig) {
        let limiter = config
            .enabled
            .then(|| Arc::new(ConnectionLimiter::new(config)));
        *self
            .connection_limit
            .write()
            .unwrap_or_else(|error| error.into_inner()) = limiter;
    }

    pub fn allow_connection_rate(&self, kind: BucketKind, uid: i32, now_ns: i64) -> bool {
        match self
            .connection_limit
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
        {
            None => true,
            Some(limiter) => limiter.allow(kind, uid, now_ns),
        }
    }

    pub fn set_block_pause_until(&self, until_ms: i64) {
        self.pause_until_ms.store(until_ms, Ordering::Release);
    }

    pub fn block_paused(&self) -> bool {
        let until = self.pause_until_ms.load(Ordering::Acquire);
        until > 0 && now_ms() < until
    }

    pub fn block_pause_until(&self) -> i64 {
        self.pause_until_ms.load(Ordering::Acquire)
    }

    pub fn set_allowlist_only(&self, enabled: bool) {
        self.allowlist_only.store(enabled, Ordering::Release);
    }

    pub fn allowlist_only(&self) -> bool {
        self.allowlist_only.load(Ordering::Acquire)
    }

    pub fn set_block_response_type(&self, response_type: &str) {
        let parsed = diting_config_core::protocol::parse_response_type(response_type).code() as u32;
        self.block_response.store(parsed, Ordering::Release);
    }

    pub fn clear_dns_cache(&self) {
        self.cache.clear();
    }

    pub fn effective_block_response(&self, domain: &str) -> u32 {
        let fallback = self.block_response.load(Ordering::Acquire);
        let config = *self
            .dynamic_config
            .read()
            .unwrap_or_else(|error| error.into_inner());
        if !config.enabled {
            return fallback;
        }
        let clean = diting_config_core::rewrite::normalize_domain(domain);
        if clean.is_empty() {
            return fallback;
        }
        self.dynamic_blocks
            .response_for(&clean, &config, fallback, crate::resolver::now_ns())
    }


    pub fn note_query(&self, blocked: bool) {
        self.total_queries.fetch_add(1, Ordering::Relaxed);
        if blocked {
            self.blocked_queries.fetch_add(1, Ordering::Relaxed);
        }
    }

    pub fn total_queries(&self) -> u64 {
        self.total_queries.load(Ordering::Relaxed)
    }

    pub fn blocked_queries(&self) -> u64 {
        self.blocked_queries.load(Ordering::Relaxed)
    }

    pub fn log_row(&self, row: LogRow) {
        self.logs.push(row.build(now_ms()));
    }

    pub fn log_error(&self, message: &str) {
        if message.is_empty() {
            return;
        }
        let row: LogItem = LogRow::error_row(message, now_ms());
        self.logs.push(row);
    }


    pub fn start_standalone(self: &Arc<Self>, port: u16) -> EngineResult<()> {
        self.start_standalone_on(port, false)
    }

    pub fn start_standalone_loopback(self: &Arc<Self>, port: u16) -> EngineResult<()> {
        self.start_standalone_on(port, true)
    }

    fn start_standalone_on(self: &Arc<Self>, port: u16, loopback: bool) -> EngineResult<()> {
        let mut server = self
            .server
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(existing) = server.take() {
            existing.stop();
        }
        let started = if loopback {
            crate::standalone::start_loopback(Arc::clone(self), port)?
        } else {
            crate::standalone::start(Arc::clone(self), port)?
        };
        *server = Some(started);
        self.running.store(true, Ordering::Release);
        Ok(())
    }

    pub fn stop_standalone(&self) {
        let mut server = self
            .server
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(started) = server.take() {
            started.stop();
        }
        self.running.store(false, Ordering::Release);
    }

    pub fn stop(&self) {
        self.stop_standalone();
        self.stop_full();
        self.cache.clear();
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Acquire) || self.is_full_running()
    }

    pub fn started_at_ms(&self) -> i64 {
        self.started_at_ms
    }

    pub fn set_event_sink(&self, sink: Option<Arc<dyn EventSink>>) {
        self.logs.set_sink(sink);
    }

    pub fn standalone_port(&self) -> Option<u16> {
        self.server
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(|server| server.port())
    }


    pub fn attribution(&self) -> &Attribution {
        &self.attribution
    }

    pub fn mitm_state(&self) -> &Arc<crate::mitm::MitmState> {
        &self.mitm
    }

    pub fn connlog(&self) -> &ConnLogDedup {
        &self.connlog
    }

    pub fn record_flow(&self, key: FlowKey, app: &str, domain: &str, status: FlowStatus) {
        if let Ok(mut table) = self.flows.lock() {
            table.record(FlowEvent {
                key,
                domain: domain.to_string(),
                package: app.to_string(),
                up_delta: 0,
                down_delta: 0,
                status,
                at_ms: now_ms(),
            });
        }
    }

    pub fn flow_snapshot_json(&self, since_seq: u64, limit: usize) -> String {
        match self.flows.lock() {
            Ok(table) => table.snapshot(since_seq, limit).to_json(),
            Err(_) => concat!(
                "{\"baseSeq\":0,\"nextSeq\":0,\"total\":0,",
                "\"truncated\":false,\"sessions\":[]}"
            )
            .to_string(),
        }
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

    pub fn set_blocked_uids(&self, csv: &str) {
        let parsed = Arc::new(BlockedUids::parse_csv(csv));
        *self
            .blocked_uids
            .write()
            .unwrap_or_else(|error| error.into_inner()) = parsed;
    }

    pub fn is_uid_blocked(&self, uid: i32) -> bool {
        if uid < 0 {
            return false;
        }
        self.blocked_uids
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .is_blocked(i64::from(uid))
    }

    pub fn set_filter_http3(&self, enabled: bool) {
        self.quic_drop.store(enabled, Ordering::Release);
    }

    pub fn filter_http3(&self) -> bool {
        self.quic_drop.load(Ordering::Acquire)
    }

    pub fn set_block_encrypted_dns(&self, enabled: bool) {
        self.block_encrypted_dns.store(enabled, Ordering::Release);
    }

    pub fn block_encrypted_dns(&self) -> bool {
        self.block_encrypted_dns.load(Ordering::Acquire)
    }

    pub fn traffic(&self) -> &Arc<TrafficTracker> {
        &self.traffic
    }

    pub fn set_traffic_sink(&self, sink: Option<Arc<dyn TrafficSink>>) {
        *self
            .traffic_sink
            .write()
            .unwrap_or_else(|error| error.into_inner()) = sink;
    }

    pub fn set_tick_interval_ms(&self, millis: i64) {
        if millis <= 0 {
            return;
        }
        self.tick_interval_ms
            .store(millis as u64, Ordering::Release);
    }

    fn traffic_sink(&self) -> Option<Arc<dyn TrafficSink>> {
        self.traffic_sink
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn start_full(self: &Arc<Self>, fd: i32) -> EngineResult<()> {
        let link = TunFd::open(fd, DEFAULT_TUN_MTU).map_err(|error| {
            EngineError::state(format!("StartFull: dup TUN fd {fd} failed: {error}"))
        })?;
        self.start_full_with_link(Arc::new(link))
    }

    pub fn start_full_with_link(self: &Arc<Self>, link: Arc<dyn PacketLink>) -> EngineResult<()> {
        let mut slot = self.full.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(session) = slot.as_ref() {
            if session.is_running() {
                return Ok(());
            }
        }
        self.connlog.reset();
        if let Ok(mut flows) = self.flows.lock() {
            flows.reset();
        }
        self.total_queries.store(0, Ordering::Relaxed);
        self.blocked_queries.store(0, Ordering::Relaxed);
        let session = Session::start(Arc::clone(self), link).map_err(EngineError::state)?;
        *slot = Some(session);
        drop(slot);
        let outbound = self.outbound();
        if outbound.config().enabled() {
            outbound.report("connecting", "");
        } else {
            outbound.report("disabled", "");
        }
        self.start_traffic_ticker();
        Ok(())
    }

    pub fn stop_full(&self) {
        let session = {
            let mut slot = self.full.lock().unwrap_or_else(|error| error.into_inner());
            slot.take()
        };
        if let Some(session) = session {
            session.stop();
        }
        self.stop_traffic_ticker();
    }

    pub fn is_full_running(&self) -> bool {
        self.full
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(Session::is_running)
            .unwrap_or(false)
    }

    pub fn tun_document(&self) -> Option<serde_json::Value> {
        self.full
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(Session::document)
    }

    fn start_traffic_ticker(self: &Arc<Self>) {
        let running = Arc::new(AtomicBool::new(true));
        {
            let mut slot = self
                .ticker
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let Some(previous) = slot.take() {
                previous.store(false, Ordering::Release);
            }
            *slot = Some(Arc::clone(&running));
        }
        let engine = Arc::clone(self);
        self.spawn(async move {
            loop {
                let interval = engine.tick_interval_ms.load(Ordering::Acquire).max(100);
                tokio::time::sleep(Duration::from_millis(interval)).await;
                if !running.load(Ordering::Acquire) {
                    return;
                }
                let deltas = engine.traffic.tick();
                if let Some(sink) = engine.traffic_sink() {
                    let now = crate::resolver::now_ns();
                    let rows: Vec<(i32, i64, i64, String)> = deltas
                        .iter()
                        .map(|delta| {
                            (
                                delta.uid,
                                delta.tx as i64,
                                delta.rx as i64,
                                engine.attribution().package_for(delta.uid, now),
                            )
                        })
                        .collect();
                    sink.tick(&crate::tunnel::stats::traffic_payload(&rows));
                }
            }
        });
    }

    fn stop_traffic_ticker(&self) {
        let running = {
            let mut slot = self
                .ticker
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            slot.take()
        };
        if let Some(running) = running {
            running.store(false, Ordering::Release);
        }
    }


    pub fn stats_json(&self) -> String {
        crate::stats::engine_stats_json(self)
    }

    pub fn cache_stats_json(&self) -> String {
        crate::cache::stats_json(self.cache.stats())
    }

    pub fn cache_entries_json(&self, limit: i64) -> String {
        if limit <= 0 {
            return "[]".to_string();
        }
        let entries = self.cache.snapshot(limit.min(u32::MAX as i64) as u32);
        crate::cache::entries_json(&entries)
    }

    pub fn resolve_domain_blocking(&self, domain: &str, ipv4: bool) -> String {
        let domain = domain.to_string();
        if tokio::runtime::Handle::try_current().is_ok() {
            return tokio::task::block_in_place(|| {
                self.runtime
                    .handle()
                    .block_on(async { self.resolve_domain(&domain, ipv4).await })
            });
        }
        self.runtime
            .handle()
            .block_on(async { self.resolve_domain(&domain, ipv4).await })
    }

    pub fn cache_config(&self) -> CacheConfig {
        self.cache.policy()
    }

    pub fn dns_config(&self) -> Option<DnsConfig> {
        self.config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }


    pub async fn resolve_domain(&self, domain: &str, ipv4: bool) -> String {
        let domain = diting_config_core::rewrite::normalize_domain(domain);
        if domain.is_empty() {
            return resolve_domain_error_json("empty domain");
        }
        let qtype = if ipv4 { TYPE_A } else { TYPE_AAAA };

        if let Some(entry) = self.rewrites.lookup(&domain) {
            let ip = if ipv4 { entry.ip4 } else { entry.ip6 };
            if !ip.is_empty() {
                return resolve_domain_json(&[ip], &[REWRITE_ANSWER_TTL as i64], "rewrite", "", "");
            }
        }

        if self.filter_dns() && self.policy().is_active() && self.policy().has_rules() {
            if let Some(verdict) = self.policy().evaluate(&domain, "", qtype) {
                if verdict.blocked {
                    return resolve_domain_json(&[], &[], "blocked", &verdict.reason, "");
                }
            }
        }

        let resolver = self.resolver();
        if resolver.is_empty() {
            return resolve_domain_error_json("tunnel resolver not active");
        }

        let response = match resolver.resolve_name(&domain, qtype).await {
            Ok(response) => response,
            Err(error) => return resolve_domain_error_json(&error),
        };
        let Some(extracted) = diting_dns_core::message::extract(&response) else {
            return resolve_domain_error_json("DNS answer extract failed");
        };
        if extracted.blocked {
            return resolve_domain_json(&[], &[], "blocked", "upstream_dns", "");
        }

        let mut ips = Vec::new();
        let mut ttls = Vec::new();
        for record in &extracted.addresses {
            if (record.rrtype == TYPE_A as u8) != ipv4 || record.address.is_empty() {
                continue;
            }
            ips.push(match record.address.len() {
                4 => format_ipv4(&record.address),
                16 => diting_dns_wire::format_ipv6(&record.address),
                _ => continue,
            });
            ttls.push(record.ttl as i64);
        }
        if ips.is_empty() {
            let reason = rcode_text(extracted.rcode);
            return resolve_domain_json(&[], &[], "nodata", &reason, "");
        }
        resolve_domain_json(&ips, &ttls, "upstream", "", "")
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

fn resolve_domain_json(
    ips: &[String],
    ttls: &[i64],
    source: &str,
    reason: &str,
    error: &str,
) -> String {
    let mut document = serde_json::Map::new();
    if !ips.is_empty() {
        document.insert("ips".to_string(), serde_json::json!(ips));
    }
    if !ttls.is_empty() {
        document.insert("ttls".to_string(), serde_json::json!(ttls));
    }
    document.insert("source".to_string(), serde_json::json!(source));
    if !reason.is_empty() {
        document.insert("reason".to_string(), serde_json::json!(reason));
    }
    if !error.is_empty() {
        document.insert("error".to_string(), serde_json::json!(error));
    }
    serde_json::Value::Object(document).to_string()
}

pub fn resolve_domain_error_json(message: &str) -> String {
    let mut document = serde_json::Map::new();
    document.insert("source".to_string(), serde_json::json!(""));
    document.insert("error".to_string(), serde_json::json!(message));
    serde_json::Value::Object(document).to_string()
}

fn rcode_text(rcode: u16) -> String {
    match rcode {
        0 => "NOERROR".to_string(),
        1 => "FORMERR".to_string(),
        2 => "SERVFAIL".to_string(),
        3 => "NXDOMAIN".to_string(),
        4 => "NOTIMP".to_string(),
        5 => "REFUSED".to_string(),
        _ => "no answer records".to_string(),
    }
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}
