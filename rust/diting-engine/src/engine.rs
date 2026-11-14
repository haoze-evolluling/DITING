//! The engine: state, lifecycle, the configuration setters and the JSON documents the UI reads.
//!
//! One [`Engine`] is one Android engine instance — one `tunnel.Engine` as Kotlin saw it. It owns the
//! cache, the published policy snapshot, the rewrite table, the resolver, the log buffer and the
//! tokio runtime that serves the standalone DNS ports. It is always used behind an `Arc` (see
//! [`crate::jni`]'s handle registry), so the data path can clone it into a background refresh task
//! without the JNI layer having to reason about lifetimes.
//!
//! # What the setters do
//!
//! | Kotlin call | Here |
//! |---|---|
//! | `applyDNSConfig` | [`Engine::apply_dns_config`] |
//! | `applyRuleSnapshot` | [`Engine::apply_rule_snapshot`] |
//! | `setRewriteRules` | [`Engine::set_rewrite_rules`] |
//! | `setFilterDNS` | [`Engine::set_filter_dns`] |
//! | `setBlockResponseType` | [`Engine::set_block_response_type`] |
//! | `clearDNSCache` | [`Engine::clear_dns_cache`] |
//! | `getStats` / `getDNSCacheStats` / `getDNSCacheEntries` | [`crate::stats`] |
//! | `resolveDomain` | [`Engine::resolve_domain`] |
//! | `startStandalone` / `stopStandalone` / `stop` | [`Engine::start_standalone`] |

use std::sync::atomic::{AtomicBool, AtomicI64, AtomicU32, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, RwLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use diting_connlog_core::ConnLogDedup;
use diting_dns_cache_core::policy::Config as CacheConfig;
use diting_dns_core::block::{BlockConfig, DynamicBlocks};
use diting_dns_core::message::{query_info, TYPE_A, TYPE_AAAA};
use diting_dns_core::reply::REWRITE_ANSWER_TTL;
use diting_dns_wire::format_ipv4;
use diting_gate_core::BlockedUids;
use diting_telemetry_core::{LogItem, TrafficTracker};
use smoltcp::wire::IpEndpoint;
use tokio::runtime::Runtime;

use crate::attribution::Attribution;
use crate::cache::DnsCache;
use crate::config::DnsConfig;
use crate::dns::LogRow;
use crate::error::{EngineError, EngineResult};
use crate::logs::{BootstrapSink, EventSink, Logs};
use crate::outbound::{Outbound, StatusDispatcher, StatusSink};
use crate::policy::{rewrites_from_json, Policy, Rewrites};
use crate::protect::ProtectorHandle;
use crate::resolver::{Bootstrap, Resolver, ResolverDeps, StatsStore, UpstreamTrust};
use crate::standalone::Standalone;
use crate::tunnel::{PacketLink, Session, TunFd};

/// The Android MTU the Go engine used (`defaultTunMTU`): 1500 minus the VPN's own headers.
pub const DEFAULT_TUN_MTU: usize = 1400;

/// `TrafficCallback.onTrafficStatsTick(String)`, installed by Kotlin.
pub trait TrafficSink: Send + Sync + 'static {
    /// One JSON array of `{"uid":…,"tx":…,"rx":…}` rows.
    fn tick(&self, json: &str);
}

/// The tokio runtime, shut down without blocking.
///
/// `Runtime`'s own `Drop` waits for its blocking pool, which panics when it happens on a worker
/// thread — and the last `Arc<Engine>` can well be dropped by a task (a cancelled server loop, a
/// background refresh). `shutdown_background` is the only safe way out: tasks that are still queued
/// are dropped instead of being waited for, which is what a stopped engine wants anyway.
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

/// One engine instance.
pub struct Engine {
    started_at_ms: i64,
    runtime: EngineRuntime,
    cache: DnsCache,
    policy: Policy,
    rewrites: Rewrites,
    dynamic_blocks: DynamicBlocks,
    filter_dns: AtomicBool,
    /// `setBlockIpv6`: answer every AAAA query with an empty NOERROR (NODATA) so a client on a
    /// link whose IPv6 is unusable falls back to IPv4 instead of stalling on a dual-stack retry.
    /// Only set when the tunnel carries no IPv6.
    block_ipv6: AtomicBool,
    block_response: AtomicU32,
    /// R4: temporary pause. While `now_ms() < pause_until_ms` every policy block is skipped, so DNS
    /// still resolves but nothing is filtered. `0` means not paused.
    pause_until_ms: AtomicI64,
    /// R4: allowlist-only. When set, a name that is not explicitly allow-listed is blocked even if no
    /// block rule matches — a strict "only these pass" mode.
    allowlist_only: AtomicBool,
    dynamic_config: RwLock<BlockConfig>,
    config: RwLock<Option<DnsConfig>>,
    resolver: RwLock<Arc<Resolver>>,
    /// The statistics of every provider ever configured, keyed like `ConfigureProviders` did, so a
    /// config change keeps the health the circuit breaker and the ranking depend on.
    stats: Arc<StatsStore>,
    /// The bootstrap resolver, shared by every provider of every published resolver.
    bootstrap: Arc<Bootstrap>,
    /// The trust store the encrypted upstreams verify against (`upstreamRootPool`).
    trust: RwLock<Arc<UpstreamTrust>>,
    /// `VpnService.protect`, installed by Kotlin before the TUN starts. Shared by the resolver
    /// dialers and the bootstrap queries, so one setter covers every outbound socket.
    protector: ProtectorHandle,
    /// The outbound transports (direct / SOCKS5 / HTTP CONNECT) and their per-UID scope. Shared
    /// with the resolver's dialer so the engine's own upstream queries follow the same route.
    outbound: Arc<RwLock<Outbound>>,
    /// `OutboundProxyStatusCallback` and its `(state, message)` dedupe.
    outbound_status: Arc<StatusDispatcher>,
    logs: Arc<Logs>,
    flights: Mutex<std::collections::HashMap<Vec<u8>, crate::dns::flight::Flight>>,
    total_queries: AtomicU64,
    blocked_queries: AtomicU64,
    server: Mutex<Option<Standalone>>,
    running: AtomicBool,
    // ---- stage 3: the TUN data plane -----------------------------------------------------
    /// The UID/package callbacks and their caches.
    attribution: Attribution,
    /// `connLogSeen`: one row per `app|dest|port|proto` per session.
    connlog: ConnLogDedup,
    /// `SetBlockedUIDs`; empty until the UI pushes the list.
    blocked_uids: RwLock<Arc<BlockedUids>>,
    /// `SetFilterHttp3`: drop `UDP :443` so HTTP/3 falls back to TCP (needs the MITM UID set).
    quic_drop: AtomicBool,
    /// `SetBlockEncryptedDns`: refuse `TCP/UDP :853`.
    block_encrypted_dns: AtomicBool,
    /// The per-UID byte counters behind `TrafficCallback`.
    traffic: Arc<TrafficTracker>,
    traffic_sink: RwLock<Option<Arc<dyn TrafficSink>>>,
    tick_interval_ms: AtomicU64,
    /// The running TUN session (the fd path or the in-memory test link).
    full: Mutex<Option<Session>>,
    /// The ticker task's stop flag.
    ticker: Mutex<Option<Arc<AtomicBool>>>,
    // ---- stage 4b: MITM -----------------------------------------------------------------
    /// The root CA, the smart filter and the pushed cosmetic/request rules. One `Arc` so the
    /// relay tasks clone it instead of borrowing the engine's internals.
    mitm: Arc<crate::mitm::MitmState>,
}

impl Engine {
    /// A fresh engine. Nothing is configured yet: the cache is disabled, no snapshot is published,
    /// but the log buffer is already flushing and the runtime is ready to serve.
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

    // ---- accessors used by the query path -------------------------------------------------

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

    /// The trust store the DoH/DoT/DoQ clients verify against. Stage 4's CA inspection replaces it;
    /// the transport tests install a loopback PKI.
    pub fn upstream_trust(&self) -> Arc<UpstreamTrust> {
        self.trust
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    /// The protector every outbound socket of the engine goes through.
    pub fn protector(&self) -> ProtectorHandle {
        self.protector.clone()
    }

    /// The current outbound transport (direct or proxied) and its per-UID scope.
    pub fn outbound(&self) -> Outbound {
        self.outbound
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    /// `ConfigureOutboundProxy`: empty on success, otherwise the error text Kotlin shows.
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

    /// `SetOutboundProxyStatusCallback`; a null stops reporting.
    pub fn set_outbound_status_sink(&self, sink: Option<Arc<dyn StatusSink>>) {
        self.outbound_status.set(sink);
    }

    /// Replaces the trust store. The next `ApplyDNSConfig` (or a direct
    /// [`Engine::rebuild_resolver`]) publishes it to the transports.
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

    /// Fire-and-forget: a background refresh nobody joins.
    pub fn spawn<F>(&self, future: F)
    where
        F: std::future::Future<Output = ()> + Send + 'static,
    {
        self.runtime.handle().spawn(future);
    }

    /// A task whose handle the caller keeps, so it can be aborted when the server stops.
    pub fn spawn_task<F>(&self, future: F) -> tokio::task::JoinHandle<()>
    where
        F: std::future::Future<Output = ()> + Send + 'static,
    {
        self.runtime.handle().spawn(future)
    }

    pub fn block_on<F: std::future::Future>(&self, future: F) -> F::Output {
        self.runtime.handle().block_on(future)
    }

    // ---- configuration -------------------------------------------------------------------

    /// `ApplyDNSConfig`. The order is the old one: validate and normalize first, push the new policy
    /// into the cache, publish the providers, and only then swap the block-response mode, the dynamic
    /// config and the stored document. A rejected snapshot therefore changes nothing at all.
    pub fn apply_dns_config(&self, payload: &str) -> EngineResult<()> {
        let config = DnsConfig::from_json(payload)?;

        self.cache.apply_policy(config.cache.clone());
        self.publish_resolver(&config);
        self.block_response
            .store(config.block_response, Ordering::Release);
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

    /// Builds and publishes the resolver for `config`, closing the one it replaces.
    ///
    /// The statistics and the bootstrap parser are shared across publications (their state is the
    /// point), and the trust store is read at publish time so `set_upstream_trust` applies to the
    /// next configuration. A provider that cannot be dialed is dropped and reported as a log row
    /// instead of silently disappearing.
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

    /// `SetRewriteRules`: a malformed payload is logged and the previous table keeps serving.
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

    /// `setBlockIpv6`: suppress AAAA at the DNS stage while the tunnel has no usable IPv6. Kotlin
    /// derives it from the tunnel plan's `enableIpv6`, so `auto` with no reachable IPv6, and an
    /// explicit `disable`, both filter; `auto`/`prefer` with a working link do not.
    pub fn set_block_ipv6(&self, enabled: bool) {
        self.block_ipv6.store(enabled, Ordering::Release);
    }

    pub fn block_ipv6(&self) -> bool {
        self.block_ipv6.load(Ordering::Acquire)
    }

    /// `setBlockPause(untilMs)`: skip every policy block until `until_ms` (epoch ms). `0` clears it.
    /// The pause naturally expires against the wall clock, so no timer clears it.
    pub fn set_block_pause_until(&self, until_ms: i64) {
        self.pause_until_ms.store(until_ms, Ordering::Release);
    }

    /// Whether blocking is currently paused.
    pub fn block_paused(&self) -> bool {
        let until = self.pause_until_ms.load(Ordering::Acquire);
        until > 0 && now_ms() < until
    }

    /// The raw pause deadline (0 when not paused); surfaced for diagnostics.
    pub fn block_pause_until(&self) -> i64 {
        self.pause_until_ms.load(Ordering::Acquire)
    }

    /// `setAllowlistOnly(enabled)`: block anything that is not an explicit allow.
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

    /// `effectiveBlockResponseType`: the configured mode, escalated by the dynamic-block tracker for a
    /// domain that keeps being asked.
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

    // ---- counters and logging ------------------------------------------------------------

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

    /// Pushes one row through the batch buffer (`notifyLog`).
    pub fn log_row(&self, row: LogRow) {
        self.logs.push(row.build(now_ms()));
    }

    /// The engine's own log line. There is no logcat bridge in stage 1: `libditing_engine.so` is
    /// loaded by a normal Android process, so the line goes to the batch log's error channel as a
    /// row - which is where the UI's log viewer can already show it.
    pub fn log_error(&self, message: &str) {
        if message.is_empty() {
            return;
        }
        let row: LogItem = LogRow::error_row(message, now_ms());
        self.logs.push(row);
    }

    pub fn query_name(&self, query: &[u8]) -> String {
        query_info(query).name
    }

    pub fn query_type(&self, query: &[u8]) -> u16 {
        query_info(query).qtype
    }

    // ---- lifecycle -----------------------------------------------------------------------

    /// Starts the standalone DNS server on `port` (UDP + TCP, IPv4 + IPv6 when available).
    pub fn start_standalone(self: &Arc<Self>, port: u16) -> EngineResult<()> {
        let mut server = self
            .server
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if let Some(existing) = server.take() {
            existing.stop();
        }
        let started = crate::standalone::start(Arc::clone(self), port)?;
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

    /// `Stop`: stop serving and release the resolver and cache handles. The engine object stays
    /// usable, exactly like the Go one (Kotlin calls `stop()` before dropping the reference).
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

    /// The port the standalone server actually listens on (`None` when it is not running).
    pub fn standalone_port(&self) -> Option<u16> {
        self.server
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .as_ref()
            .map(|server| server.port())
    }

    // ---- stage 3: attribution, settings and the TUN session -------------------------------

    /// The UID/package callbacks and the 2 s / 60 s caches in front of them.
    pub fn attribution(&self) -> &Attribution {
        &self.attribution
    }

    /// The MITM session and the settings Kotlin pushes (`startStackMitm`, `setCosmeticRules`, …).
    pub fn mitm_state(&self) -> &Arc<crate::mitm::MitmState> {
        &self.mitm
    }

    /// `connLogSeen`, reset when a new TUN session starts.
    pub fn connlog(&self) -> &ConnLogDedup {
        &self.connlog
    }

    /// `resolveFlowUID`: app endpoint first, destination second (Android's direction).
    pub fn flow_uid(&self, protocol: i32, app: IpEndpoint, server: IpEndpoint) -> i32 {
        self.attribution
            .uid_for(protocol, app, server, crate::resolver::now_ns())
    }

    /// The package behind a UID, or an empty string.
    pub fn app_name(&self, uid: i32) -> String {
        self.attribution.package_for(uid, crate::resolver::now_ns())
    }

    /// `logConnection`'s `app` column: the package, `uid:N`, or `unknown`.
    pub fn display_name(&self, uid: i32) -> String {
        self.attribution
            .display_name(uid, crate::resolver::now_ns())
    }

    /// `SetBlockedUIDs`: the kernel parses the CSV and keeps the positive ids.
    pub fn set_blocked_uids(&self, csv: &str) {
        let parsed = Arc::new(BlockedUids::parse_csv(csv));
        *self
            .blocked_uids
            .write()
            .unwrap_or_else(|error| error.into_inner()) = parsed;
    }

    /// `isUIDBlocked`.
    pub fn is_uid_blocked(&self, uid: i32) -> bool {
        if uid < 0 {
            return false;
        }
        self.blocked_uids
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .is_blocked(i64::from(uid))
    }

    /// `SetFilterHttp3`.
    pub fn set_filter_http3(&self, enabled: bool) {
        self.quic_drop.store(enabled, Ordering::Release);
    }

    pub fn filter_http3(&self) -> bool {
        self.quic_drop.load(Ordering::Acquire)
    }

    /// `SetBlockEncryptedDns`.
    pub fn set_block_encrypted_dns(&self, enabled: bool) {
        self.block_encrypted_dns.store(enabled, Ordering::Release);
    }

    pub fn block_encrypted_dns(&self) -> bool {
        self.block_encrypted_dns.load(Ordering::Acquire)
    }

    /// The per-UID byte counters; the flow handlers record `tx`/`rx` through this.
    pub fn traffic(&self) -> &Arc<TrafficTracker> {
        &self.traffic
    }

    /// Installs `TrafficCallback`; the ticker only runs while a TUN session is up.
    pub fn set_traffic_sink(&self, sink: Option<Arc<dyn TrafficSink>>) {
        *self
            .traffic_sink
            .write()
            .unwrap_or_else(|error| error.into_inner()) = sink;
    }

    /// `SetTickIntervalMs`: the UI stretches the cadence when the screen is off.
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

    /// Starts the TUN data plane on the duplicated descriptor (`StartFull`).
    pub fn start_full(self: &Arc<Self>, fd: i32) -> EngineResult<()> {
        let link = TunFd::open(fd, DEFAULT_TUN_MTU).map_err(|error| {
            EngineError::state(format!("StartFull: dup TUN fd {fd} failed: {error}"))
        })?;
        self.start_full_with_link(Arc::new(link))
    }

    /// The same session over any [`PacketLink`]: the host tests' in-memory device.
    pub fn start_full_with_link(self: &Arc<Self>, link: Arc<dyn PacketLink>) -> EngineResult<()> {
        let mut slot = self.full.lock().unwrap_or_else(|error| error.into_inner());
        if let Some(session) = slot.as_ref() {
            if session.is_running() {
                return Ok(());
            }
        }
        // A new session logs every flow once, like `connLogSeen.reset()` in `StartFull`.
        self.connlog.reset();
        // `StartFull` also restarted the query counters for the new session.
        self.total_queries.store(0, Ordering::Relaxed);
        self.blocked_queries.store(0, Ordering::Relaxed);
        let session = Session::start(Arc::clone(self), link).map_err(EngineError::state)?;
        *slot = Some(session);
        drop(slot);
        // `StartFull` reported the proxy state before the stack came up; the dials then report
        // `ready`/`error` through the same dispatcher.
        let outbound = self.outbound();
        if outbound.config().enabled() {
            outbound.report("connecting", "");
        } else {
            outbound.report("disabled", "");
        }
        self.start_traffic_ticker();
        Ok(())
    }

    /// `StopFull` / `ReleaseTun`: stops the data plane; idempotent.
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

    /// The `"tun"` object for `getStats`; `None` while no TUN session is running.
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
                // Always tick, even with no data: the empty `[]` still ages the rate to zero, so a
                // dashboard curve falls back to 0 when traffic stops instead of freezing its last
                // value. The cost is one small JSON callback per interval while the tunnel is up.
                if let Some(sink) = engine.traffic_sink() {
                    sink.tick(&crate::tunnel::stats::traffic_json(&deltas));
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

    // ---- documents the JNI layer returns verbatim ----------------------------------------

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

    /// The blocking form of [`Engine::resolve_domain`] for host callers and the JNI entry point.
    ///
    /// A JNI caller is a plain thread; a host test may already be inside a runtime, so the call is
    /// wrapped in `block_in_place` in that case (`resolve_domain` itself is async and cannot be
    /// awaited from a synchronous entry point).
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

    // ---- diagnostics ---------------------------------------------------------------------

    /// `ResolveDomain`: rewrite first, then the policy, then the configured upstream. Returns the
    /// JSON document `DnsLookupProbe` parses, including its exact error texts.
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
        self.stop_standalone();
    }
}

/// `resolveDomainResult` with `omitempty` on everything but `source`.
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
    // `json.Marshal(resolveDomainResult{Error: message})`: only `source` and `error` are present.
    let mut document = serde_json::Map::new();
    document.insert("source".to_string(), serde_json::json!(""));
    document.insert("error".to_string(), serde_json::json!(message));
    serde_json::Value::Object(document).to_string()
}

/// `dns.RcodeToString`, then the fallback the old code used.
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
