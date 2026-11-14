//! The upstream resolver: providers, the four transports, the scheduler and the race log.
//!
//! This replaces `resolver.go` + `resolver_plain.go` / `resolver_dot.go` / `resolver_doh.go` /
//! `resolver_doq.go` / `resolver_strategy.go` / `bootstrap_resolver.go`. The split is the same one
//! the migration plan draws: decisions come from the kernels, sockets and message handling are here.
//!
//! | Concern | Kernel |
//! |---|---|
//! | attempt order, per-attempt budgets, hedge, encrypted grace window, race-log fields | [`diting_resolver_core::Schedule`] |
//! | SRTT/RTTVAR, failure ratio, circuit breaker, UDP retry interval | [`diting_resolver_core::ProviderStats`] |
//! | bootstrap health, weighted pick, host cache | [`diting_bootstrap_core::BootstrapKernel`] |
//! | endpoint split, dial address, framing, truncation, DoT length rules | [`diting_upstream_core`] |
//! | DoH status table and the one-shot `EOF` retry | [`diting_upstream_core::doh`] |
//!
//! Everything else is new Rust: the four socket paths ([`plain`], [`dot`], [`doh`], [`doq`]), the
//! bootstrap UDP queries ([`bootstrap`]), the platform trust store ([`trust`]) and the dialer
//! ([`dial`]) that stage 3 will make call `VpnService.protect`.
//!
//! # Statistics survive a reconfiguration
//!
//! Go keyed `providerStatsMap` by provider id (or `proto:server:url`) on the parent resolver, and
//! `ConfigureProviders` reused the existing entry. Here the map is [`StatsStore`], owned by the
//! engine and handed to every new [`Resolver`], so a config change keeps the per-provider health —
//! which is what the circuit breaker and the smart-prediction ranking depend on.
//!
//! # Providers that cannot be used
//!
//! A provider whose endpoint cannot be parsed is dropped from the query path and reported through
//! [`Resolver::skipped`]; the engine turns those lines into log rows. With no provider left, queries
//! fail with [`NO_PROVIDER`] — the same visible outcome as an unreachable upstream, and the message
//! `ResolveDomain` already surfaced in stage 1.

pub mod bootstrap;
pub mod dial;
pub mod doh;
pub mod doq;
pub mod dot;
pub mod plain;
pub mod schedule;
pub mod trust;

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use diting_config_core::endpoint::parse_doq_url;
use diting_config_core::protocol::Protocol;
use diting_resolver_core::ProviderStats;
use diting_upstream_core::endpoint::{split_target, TargetProtocol};
use http::Uri;

use crate::config::{DnsConfig, Provider as ConfigProvider};
use crate::logs::RaceEvent;
use crate::protect::ProtectorHandle;

pub use bootstrap::Bootstrap;
use dial::Dialer;
pub use trust::UpstreamTrust;

/// The failure text of a resolver with no usable provider (`ResolveDomain` reports it verbatim).
pub const NO_PROVIDER: &str = "no usable DNS provider";

/// One statistics handle per provider key, kept across configuration changes.
#[derive(Default)]
pub struct StatsStore {
    map: Mutex<HashMap<String, Arc<ProviderStats>>>,
}

impl StatsStore {
    /// The statistics of one provider, created on first use. `key` is the provider id, or
    /// `proto:server:url` when the config carries no id (`ConfigureProviders`' `statsKey`).
    pub fn get(&self, key: &str) -> Arc<ProviderStats> {
        let mut map = self.lock();
        Arc::clone(
            map.entry(key.to_string())
                .or_insert_with(|| Arc::new(ProviderStats::new())),
        )
    }

    fn lock(&self) -> MutexGuard<'_, HashMap<String, Arc<ProviderStats>>> {
        self.map.lock().unwrap_or_else(|error| error.into_inner())
    }
}

/// What a resolver needs from the engine: the trust store, the shared bootstrap resolver, the
/// statistics that outlive a reconfiguration and the protector every dial goes through.
pub struct ResolverDeps {
    pub trust: Arc<UpstreamTrust>,
    pub bootstrap: Arc<Bootstrap>,
    pub stats: Arc<StatsStore>,
    pub protector: ProtectorHandle,
    /// The outbound transport the upstream dials follow (`scope:"all"`), shared with the engine so
    /// a reconfiguration applies to the next query.
    pub outbound: Option<Arc<std::sync::RwLock<crate::outbound::Outbound>>>,
}

/// One configured provider plus everything parsed once at configure time.
pub(crate) struct Provider {
    pub id: String,
    pub protocol: Protocol,
    /// The host used for SNI, the bootstrap lookup and the DoT/DoQ pool keys (`dns.google`), never
    /// the resolved address.
    pub host: String,
    /// The port as configured or defaulted (`53` / `853` / `443`).
    pub port: String,
    /// The DoH URL, parsed once; `None` for the other protocols.
    pub doh_uri: Option<Uri>,
    pub stats: Arc<ProviderStats>,
}

impl Provider {
    pub(crate) fn encrypted(&self) -> bool {
        self.protocol != Protocol::Plain
    }
}

/// The published resolver state. Immutable after [`Resolver::configured`], so the query path needs
/// no lock.
pub(crate) struct Inner {
    pub providers: Vec<Provider>,
    pub mode: &'static str,
    pub race_max_parallel: i64,
    pub skipped: Vec<String>,
    pub dial: Dialer,
    pub doh: Option<doh::DohClient>,
    pub dot: Option<dot::DotClient>,
    pub doq: Option<doq::DoqClient>,
}

/// The resolver one engine configuration publishes.
#[derive(Clone)]
pub struct Resolver {
    inner: Arc<Inner>,
}

impl Resolver {
    /// The state a fresh engine starts in: no providers, no transports, the shared dependencies
    /// already installed so the first `ApplyDNSConfig` only has to publish.
    pub fn empty(deps: ResolverDeps) -> Self {
        Self {
            inner: Arc::new(Inner {
                providers: Vec::new(),
                mode: diting_config_core::mode::MODE_SINGLE,
                race_max_parallel: 0,
                skipped: Vec::new(),
                dial: Dialer::new(deps.bootstrap, deps.protector),
                // `empty` runs before any config, so there is nothing to route yet.
                doh: None,
                dot: None,
                doq: None,
            }),
        }
    }

    /// Builds the resolver for one normalized config.
    pub fn configured(config: &DnsConfig, deps: ResolverDeps) -> Self {
        deps.bootstrap.update(&config.bootstrap);

        let mut skipped = Vec::new();
        let mut providers = Vec::new();
        for provider in &config.providers {
            match build_provider(provider, &deps.stats) {
                Ok(built) => providers.push(built),
                Err(reason) => skipped.push(reason),
            }
        }

        let wants = |protocol: Protocol| providers.iter().any(|entry| entry.protocol == protocol);
        let dial = Dialer::new(deps.bootstrap, deps.protector).with_outbound(deps.outbound.clone());
        let doh = wants(Protocol::Doh)
            .then(|| doh::DohClient::new(Arc::clone(&deps.trust), dial.clone()));
        let dot = wants(Protocol::Dot).then(|| dot::DotClient::new(&deps.trust));
        let doq = if wants(Protocol::Doq) {
            match doq::DoqClient::new(&deps.trust) {
                Ok(client) => Some(client),
                Err(error) => {
                    // A DoQ client that cannot be built makes every DoQ provider unusable; say so
                    // instead of failing each query with the same opaque error.
                    skipped.push(format!("DoQ transport unavailable: {error}"));
                    providers.retain(|entry| entry.protocol != Protocol::Doq);
                    None
                }
            }
        } else {
            None
        };

        Self {
            inner: Arc::new(Inner {
                providers,
                mode: config.mode,
                race_max_parallel: config.race_max_parallel,
                skipped,
                dial,
                doh,
                dot,
                doq,
            }),
        }
    }

    /// The reasons providers were dropped, in configure order.
    pub fn skipped(&self) -> &[String] {
        &self.inner.skipped
    }

    pub fn provider_count(&self) -> usize {
        self.inner.providers.len()
    }

    pub fn mode(&self) -> &'static str {
        self.inner.mode
    }

    pub fn is_empty(&self) -> bool {
        self.inner.providers.is_empty()
    }

    pub fn bootstrap(&self) -> &Bootstrap {
        self.inner.dial.bootstrap()
    }

    /// The dialer (bootstrap + protector) the transports use.
    pub fn dialer(&self) -> &Dialer {
        &self.inner.dial
    }

    /// Resolves one query. The returned race event is what the engine forwards to
    /// `RaceLogCallback` after stamping the question; `Err` carries the last transport error, which
    /// the caller turns into SERVFAIL plus a log row.
    pub async fn resolve(&self, query: &[u8]) -> (Result<Vec<u8>, String>, Option<RaceEvent>) {
        schedule::resolve(&self.inner, query).await
    }

    /// Resolves one `(domain, qtype)` pair for the diagnostics panel (`ResolveDomain`).
    pub async fn resolve_name(&self, domain: &str, qtype: u16) -> Result<Vec<u8>, String> {
        let query = build_query(domain, qtype);
        self.resolve(&query).await.0
    }

    /// The provider statistics snapshots, in provider order.
    pub fn stats(&self) -> Vec<diting_resolver_core::stats::Snapshot> {
        self.inner
            .providers
            .iter()
            .map(|provider| provider.stats.snapshot())
            .collect()
    }

    /// Whether any DoH provider has advertised an HTTP/3 endpoint (`Alt-Svc: h3`). N7's upgrade
    /// signal; `false` when no DoH transport is configured.
    pub fn doh3_ready(&self) -> bool {
        self.inner
            .doh
            .as_ref()
            .map(|doh| doh.doh3_ready())
            .unwrap_or(false)
    }

    /// `Shutdown`: closes the pooled DoT connections and the DoQ sessions.
    pub fn shutdown(&self) {
        if let Some(dot) = &self.inner.dot {
            dot.close_all();
        }
        if let Some(doq) = &self.inner.doq {
            doq.close();
        }
    }
}

/// Parses one provider. The endpoint validation already happened in `diting-config-core` (with the
/// user-visible error texts), so a failure here means the normalized config cannot be dialed at all.
fn build_provider(provider: &ConfigProvider, stats: &StatsStore) -> Result<Provider, String> {
    let key = if provider.id.is_empty() {
        format!(
            "{}:{}:{}",
            provider.protocol.name(),
            provider.server,
            provider.url
        )
    } else {
        provider.id.clone()
    };
    let stats = stats.get(&key);

    let (host, port, doh_uri) = match provider.protocol {
        Protocol::Plain => {
            let (host, port) = split_target(&provider.server, TargetProtocol::Plain);
            (host, port, None)
        }
        Protocol::Dot => {
            let (host, port) = split_target(&provider.server, TargetProtocol::Dot);
            (host, port, None)
        }
        Protocol::Doh => {
            let uri: Uri = provider
                .url
                .parse()
                .map_err(|_| format!("provider {key}: DOH URL is not an absolute URI"))?;
            let host = uri
                .host()
                .ok_or_else(|| format!("provider {key}: DOH URL has no host"))?
                .to_string();
            let port = uri.port_u16().unwrap_or(443).to_string();
            (host, port, Some(uri))
        }
        Protocol::Doq => {
            let (host, port) = parse_doq_url(&provider.url);
            if host.is_empty() {
                return Err(format!("provider {key}: DOQ URL has no host"));
            }
            (host, port, None)
        }
    };

    Ok(Provider {
        id: provider.id.clone(),
        protocol: provider.protocol,
        host,
        port,
        doh_uri,
        stats,
    })
}

/// `dns.Msg.SetQuestion(Fqdn(domain), qtype)` + `RecursionDesired`, for `ResolveDomain` and the
/// bootstrap lookups.
pub fn build_query(domain: &str, qtype: u16) -> Vec<u8> {
    let mut out = vec![0u8; 12];
    out[0..2].copy_from_slice(&random_id().to_be_bytes());
    out[2] = 0x01; // RD
    out[5] = 1; // QDCOUNT
    let name = domain.strip_suffix('.').unwrap_or(domain);
    for label in name.split('.') {
        out.push(label.len() as u8);
        out.extend_from_slice(label.as_bytes());
    }
    out.push(0);
    out.extend_from_slice(&qtype.to_be_bytes());
    out.extend_from_slice(&1u16.to_be_bytes());
    out
}

fn random_id() -> u16 {
    // A transaction id only has to differ between in-flight queries; the clock plus a counter is
    // enough and needs no RNG dependency.
    use std::sync::atomic::{AtomicU16, Ordering};
    static COUNTER: AtomicU16 = AtomicU16::new(0);
    let counter = COUNTER.fetch_add(1, Ordering::Relaxed);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.subsec_nanos() as u16)
        .unwrap_or(0);
    counter ^ nanos
}

pub fn now_ns() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos() as i64)
        .unwrap_or(0)
}

pub fn now_ms() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_millis() as i64)
        .unwrap_or(0)
}

pub(crate) fn elapsed_ns(since: Instant) -> i64 {
    since.elapsed().as_nanos() as i64
}
