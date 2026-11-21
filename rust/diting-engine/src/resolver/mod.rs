pub mod bootstrap;
pub mod dial;
pub mod doh;
pub mod doh3;
pub mod doq;
pub mod dot;
pub mod pin;
pub mod plain;
pub mod schedule;
mod session;
mod system;
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
pub use system::SystemDns;
pub use trust::UpstreamTrust;

pub const NO_PROVIDER: &str = "no usable DNS provider";

#[derive(Default)]
pub struct StatsStore {
    map: Mutex<HashMap<String, Arc<ProviderStats>>>,
}

impl StatsStore {
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

pub struct ResolverDeps {
    pub trust: Arc<UpstreamTrust>,
    pub bootstrap: Arc<Bootstrap>,
    pub stats: Arc<StatsStore>,
    pub protector: ProtectorHandle,
    pub outbound: Option<Arc<std::sync::RwLock<crate::outbound::Outbound>>>,
    pub system_dns: SystemDns,
}

pub(crate) struct Provider {
    pub id: String,
    pub protocol: Protocol,
    pub host: String,
    pub port: String,
    pub doh_uri: Option<Uri>,
    pub pin: Option<[u8; 32]>,
    pub force_h3: bool,
    pub stats: Arc<ProviderStats>,
}

impl Provider {
    pub(crate) fn encrypted(&self) -> bool {
        self.protocol != Protocol::Plain
    }
}

pub(crate) struct Inner {
    pub providers: Vec<Provider>,
    pub mode: &'static str,
    pub race_max_parallel: i64,
    pub skipped: Vec<String>,
    pub dial: Dialer,
    pub doh: Option<doh::DohClient>,
    pub doh3: Option<doh3::Doh3Client>,
    pub dot: Option<dot::DotClient>,
    pub doq: Option<doq::DoqClient>,
    pub system_dns: SystemDns,
}

#[derive(Clone)]
pub struct Resolver {
    inner: Arc<Inner>,
}

impl Resolver {
    pub fn empty(deps: ResolverDeps) -> Self {
        Self {
            inner: Arc::new(Inner {
                providers: Vec::new(),
                mode: diting_config_core::mode::MODE_SINGLE,
                race_max_parallel: 0,
                skipped: Vec::new(),
                dial: Dialer::new(deps.bootstrap, deps.protector),
                doh: None,
                doh3: None,
                dot: None,
                doq: None,
                system_dns: deps.system_dns,
            }),
        }
    }

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

        let trust =
            if providers.iter().any(|provider| provider.pin.is_some()) {
                Arc::new(deps.trust.with_pin_hashes(
                    providers.iter().filter_map(|provider| {
                        provider.pin.map(|pin| (provider.host.as_str(), pin))
                    }),
                ))
            } else {
                Arc::clone(&deps.trust)
            };

        let wants_doh = providers
            .iter()
            .any(|entry| entry.protocol == Protocol::Doh);
        let wants_dot = providers
            .iter()
            .any(|entry| entry.protocol == Protocol::Dot);
        let wants_doq = providers
            .iter()
            .any(|entry| entry.protocol == Protocol::Doq);
        let dial = Dialer::new(deps.bootstrap, deps.protector).with_outbound(deps.outbound.clone());
        let doh = wants_doh.then(|| doh::DohClient::new(Arc::clone(&trust), dial.clone()));
        let doh3 = wants_doh
            .then(|| doh3::Doh3Client::new(&trust).ok())
            .flatten();
        if doh3.is_none() && providers.iter().any(|provider| provider.force_h3) {
            skipped.push("DoH3 transport unavailable".to_string());
            providers.retain(|provider| !provider.force_h3);
        }
        let dot = wants_dot.then(|| dot::DotClient::new(&trust));
        let doq = if wants_doq {
            match doq::DoqClient::new(&trust) {
                Ok(client) => Some(client),
                Err(error) => {
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
                doh3,
                dot,
                doq,
                system_dns: deps.system_dns,
            }),
        }
    }

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

    pub fn dialer(&self) -> &Dialer {
        &self.inner.dial
    }

    pub async fn resolve(&self, query: &[u8]) -> (Result<Vec<u8>, String>, Option<RaceEvent>) {
        schedule::resolve(&self.inner, query).await
    }

    pub async fn resolve_name(&self, domain: &str, qtype: u16) -> Result<Vec<u8>, String> {
        let query = build_query(domain, qtype);
        self.resolve(&query).await.0
    }

    pub fn stats(&self) -> Vec<diting_resolver_core::stats::Snapshot> {
        self.inner
            .providers
            .iter()
            .map(|provider| provider.stats.snapshot())
            .collect()
    }

    pub fn provider_stats(&self) -> Vec<(String, diting_resolver_core::stats::Snapshot)> {
        self.inner
            .providers
            .iter()
            .map(|provider| (provider.id.clone(), provider.stats.snapshot()))
            .collect()
    }

    pub fn doh3_ready(&self) -> bool {
        self.inner.doh3.is_some()
            && self
                .inner
                .doh
                .as_ref()
                .map(|doh| doh.doh3_ready())
                .unwrap_or(false)
    }

    pub fn shutdown(&self) {
        if let Some(dot) = &self.inner.dot {
            dot.close_all();
        }
        if let Some(doq) = &self.inner.doq {
            doq.detach();
        }
    }

    /// 网络切换后丢弃旧链路上的连接与健康度，让下一轮查询重新探测。
    pub fn reset_health(&self) {
        self.inner.system_dns.clear_degraded();
        self.inner.dial.bootstrap().reset();
        if let Some(dot) = &self.inner.dot {
            dot.close_all();
        }
        if let Some(doq) = &self.inner.doq {
            doq.detach();
        }
        for provider in &self.inner.providers {
            provider.stats.reset();
        }
    }
}

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
    let pin = if provider.pin.trim().is_empty() {
        None
    } else {
        Some(
            crate::resolver::pin::parse_pin(&provider.pin)
                .map_err(|error| format!("provider {key}: {error}"))?,
        )
    };
    if provider.force_h3 && provider.protocol != Protocol::Doh {
        return Err(format!("provider {key}: force_h3 is only valid for DoH"));
    }

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
        pin,
        force_h3: provider.force_h3,
        stats,
    })
}

pub fn build_query(domain: &str, qtype: u16) -> Vec<u8> {
    let mut out = vec![0u8; 12];
    out[0..2].copy_from_slice(&random_id().to_be_bytes());
    out[2] = 0x01;
    out[5] = 1;
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
