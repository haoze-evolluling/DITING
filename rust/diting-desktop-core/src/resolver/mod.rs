pub mod settings;
pub mod trust;

use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::Duration;

use diting_config_core::protocol::Protocol;
use diting_dns_cache_core::policy::Config as CacheConfig;
use diting_dns_core::block::BlockConfig;
use diting_engine::config::{
    BootstrapIpJson, BootstrapJson, DnsConfig, PrivacyPolicy, Provider as EngineProvider,
};
use diting_engine::logs::{BootstrapEvent, BootstrapSink};
use diting_engine::protect::ProtectorHandle;
use diting_engine::resolver::{Bootstrap, Resolver, ResolverDeps, StatsStore};

pub use settings::{
    BootstrapServerSettings, BootstrapSettings, ProviderSettings, ResolverSettings,
    DEFAULT_FALLBACK_RCODES, DEFAULT_FALLBACK_TIMEOUT_MS,
};
pub use trust::os_trust;

struct SilentBootstrap;

impl BootstrapSink for SilentBootstrap {
    fn bootstrap(&self, _event: &BootstrapEvent) {}
}

pub struct ResolverSet {
    primary: Resolver,
    fallback: Option<Resolver>,
    routes: Vec<(String, Resolver)>,
    groups: HashMap<String, Resolver>,
    fallback_timeout: Option<Duration>,
    fallback_rcodes: Vec<i32>,
    fallback_on_error: bool,
    skipped: Vec<String>,
    provider_count: usize,
}

impl ResolverSet {
    pub fn skipped(&self) -> &[String] {
        &self.skipped
    }

    pub fn provider_count(&self) -> usize {
        self.provider_count
    }

    pub fn provider_stats(&self) -> Vec<(String, diting_resolver_core::stats::Snapshot)> {
        self.primary.provider_stats()
    }

    pub async fn resolve(&self, query: &[u8], group: &str) -> Result<Vec<u8>, String> {
        self.resolve_attributed(query, group).await.0
    }

    pub async fn resolve_attributed(
        &self,
        query: &[u8],
        group: &str,
    ) -> (Result<Vec<u8>, String>, Option<String>) {
        let resolver = self.select(query, group);
        let (outcome, provider) = match self.fallback_timeout {
            Some(timeout) => match tokio::time::timeout(timeout, resolver.resolve(query)).await {
                Ok((result, event)) => (result, event_provider(event)),
                Err(_) => (
                    Err("primary resolver timed out".to_string()),
                    Some("primary timeout".to_string()),
                ),
            },
            None => {
                let (result, event) = resolver.resolve(query).await;
                (result, event_provider(event))
            }
        };

        let should_fallback = match &outcome {
            Ok(response) => self
                .fallback_rcodes
                .iter()
                .any(|code| response_rcode(response) == Some(*code)),
            Err(_) => self.fallback_on_error,
        };
        if should_fallback {
            if let Some(fallback) = &self.fallback {
                let (result, event) = fallback.resolve(query).await;
                return (result, event_provider(event).or(provider));
            }
        }
        (outcome, provider)
    }

    fn select(&self, query: &[u8], group: &str) -> &Resolver {
        if !group.is_empty() && group != "default" {
            if let Some(resolver) = self.groups.get(group) {
                return resolver;
            }
        }
        if let Some(domain) = query_domain(query) {
            if let Some(resolver) = self.match_route(&domain) {
                return resolver;
            }
        }
        &self.primary
    }

    fn match_route(&self, domain: &str) -> Option<&Resolver> {
        if self.routes.is_empty() {
            return None;
        }
        let cleaned = domain.trim_end_matches('.').to_ascii_lowercase();
        let mut current = cleaned.as_str();
        loop {
            if let Some((_, resolver)) = self.routes.iter().find(|(suffix, _)| suffix == current) {
                return Some(resolver);
            }
            let index = current.find('.')?;
            current = &current[index + 1..];
        }
    }

    pub fn shutdown(&self) {
        self.primary.shutdown();
        if let Some(fallback) = &self.fallback {
            fallback.shutdown();
        }
        for (_, resolver) in &self.routes {
            resolver.shutdown();
        }
        for resolver in self.groups.values() {
            resolver.shutdown();
        }
    }
}

pub struct DesktopResolver {
    current: RwLock<Arc<ResolverSet>>,
    trust: Arc<diting_engine::resolver::UpstreamTrust>,
    stats: Arc<StatsStore>,
    bootstrap: Arc<Bootstrap>,
    protector: ProtectorHandle,
}

impl DesktopResolver {
    pub fn new() -> Self {
        let protector = ProtectorHandle::new();
        let bootstrap = Arc::new(Bootstrap::with_protector(
            Arc::new(SilentBootstrap),
            protector.clone(),
        ));
        Self {
            current: RwLock::new(Arc::new(ResolverSet {
                primary: Resolver::empty(ResolverDeps {
                    trust: os_trust(),
                    bootstrap: Arc::clone(&bootstrap),
                    stats: Arc::new(StatsStore::default()),
                    protector: protector.clone(),
                    outbound: None,
                }),
                fallback: None,
                routes: Vec::new(),
                groups: HashMap::new(),
                fallback_timeout: None,
                fallback_rcodes: DEFAULT_FALLBACK_RCODES.to_vec(),
                fallback_on_error: true,
                skipped: Vec::new(),
                provider_count: 0,
            })),
            trust: os_trust(),
            stats: Arc::new(StatsStore::default()),
            bootstrap,
            protector,
        }
    }

    pub fn current(&self) -> Arc<ResolverSet> {
        self.current
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    pub fn configure(
        &self,
        settings: &ResolverSettings,
        groups: &[(String, Vec<String>)],
    ) -> Arc<ResolverSet> {
        let pins: Vec<(String, [u8; 32])> = settings
            .providers
            .iter()
            .chain(settings.fallback_providers.iter())
            .filter_map(|provider| {
                let host = provider_host(provider)?;
                let pin = diting_engine::resolver::pin::parse_pin(&provider.pin).ok()?;
                Some((host, pin))
            })
            .collect();
        let trust = if pins.is_empty() {
            Arc::clone(&self.trust)
        } else {
            Arc::new(self.trust.with_pin_hashes(pins))
        };

        let primary_config = dns_config(settings, &settings.providers);
        let primary = Resolver::configured(&primary_config, self.deps(&trust));
        let fallback = (!settings.fallback_providers.is_empty()).then(|| {
            let config = dns_config(settings, &settings.fallback_providers);
            Resolver::configured(&config, self.deps(&trust))
        });

        let mut routes: Vec<(String, Resolver)> = settings
            .conditional_routes
            .iter()
            .filter_map(|(pattern, upstream)| {
                let provider = parse_route(upstream, pattern)?;
                let config = dns_config(settings, std::slice::from_ref(&provider));
                Some((
                    clean_suffix(pattern),
                    Resolver::configured(&config, self.deps(&trust)),
                ))
            })
            .collect();
        routes.sort_by_key(|route| std::cmp::Reverse(route.0.len()));

        let group_resolvers = groups
            .iter()
            .filter(|(_, ids)| !ids.is_empty())
            .filter_map(|(group, ids)| {
                let providers: Vec<ProviderSettings> = ids
                    .iter()
                    .filter_map(|id| {
                        settings
                            .providers
                            .iter()
                            .find(|provider| &provider.id == id)
                            .cloned()
                    })
                    .collect();
                if providers.is_empty() {
                    return None;
                }
                let config = dns_config(settings, &providers);
                Some((
                    group.clone(),
                    Resolver::configured(&config, self.deps(&trust)),
                ))
            })
            .collect();

        let set = Arc::new(ResolverSet {
            skipped: primary.skipped().to_vec(),
            provider_count: primary.provider_count(),
            fallback_timeout: settings.effective_timeout(),
            fallback_rcodes: settings.effective_rcodes(),
            fallback_on_error: settings.fallback_on_error(),
            primary,
            fallback,
            routes,
            groups: group_resolvers,
        });
        let previous = {
            let mut guard = self
                .current
                .write()
                .unwrap_or_else(|error| error.into_inner());
            std::mem::replace(&mut *guard, Arc::clone(&set))
        };
        previous.shutdown();
        set
    }

    pub async fn resolve(&self, query: &[u8], group: &str) -> Result<Vec<u8>, String> {
        self.current().resolve(query, group).await
    }

    pub async fn resolve_attributed(
        &self,
        query: &[u8],
        group: &str,
    ) -> (Result<Vec<u8>, String>, Option<String>) {
        self.current().resolve_attributed(query, group).await
    }

    pub fn provider_stats(&self) -> Vec<(String, diting_resolver_core::stats::Snapshot)> {
        self.current().provider_stats()
    }

    fn deps(&self, trust: &Arc<diting_engine::resolver::UpstreamTrust>) -> ResolverDeps {
        ResolverDeps {
            trust: Arc::clone(trust),
            bootstrap: Arc::clone(&self.bootstrap),
            stats: Arc::clone(&self.stats),
            protector: self.protector.clone(),
            outbound: None,
        }
    }
}

impl Default for DesktopResolver {
    fn default() -> Self {
        Self::new()
    }
}

impl Drop for DesktopResolver {
    fn drop(&mut self) {
        self.current().shutdown();
    }
}

fn dns_config(settings: &ResolverSettings, providers: &[ProviderSettings]) -> DnsConfig {
    let mode = match settings.mode.trim().to_ascii_lowercase().as_str() {
        "single" => "single",
        "parallel_race" | "race" | "brute_force_parallel" => "parallel_race",
        "smart_prediction" | "prediction" => "smart_prediction",
        _ => "primary_backup",
    };
    DnsConfig {
        mode,
        providers: providers.iter().map(engine_provider).collect(),
        block_response: 0,
        dynamic_response: BlockConfig {
            enabled: false,
            request_threshold: 0,
            window_ns: 0,
            nx_domain_ns: 0,
        },
        cache: CacheConfig::default(),
        bootstrap: BootstrapJson {
            enabled: settings.bootstrap.enabled,
            ips: settings
                .bootstrap
                .servers
                .iter()
                .map(|server| BootstrapIpJson {
                    id: server.id.clone(),
                    name: server.name.clone(),
                    ip: server.address.clone(),
                    weight: server.weight,
                })
                .collect(),
        },
        privacy: PrivacyPolicy::default(),
        dns64: false,
        rate_limit: diting_ratelimit_core::Config::default(),
        connection_rate_limit: diting_engine::connection_limit::Config::default(),
        race_max_parallel: settings.race_max_parallel,
    }
}

fn engine_provider(provider: &ProviderSettings) -> EngineProvider {
    let upper = provider.protocol.trim().to_ascii_uppercase();
    let (protocol, force_h3) = match upper.as_str() {
        "DOH3" | "H3" => (Protocol::Doh, true),
        "DOH" => (Protocol::Doh, false),
        "DOT" | "TLS" => (Protocol::Dot, false),
        "DOQ" | "QUIC" => (Protocol::Doq, false),
        _ => (Protocol::Plain, false),
    };
    EngineProvider {
        id: provider.id.clone(),
        protocol,
        server: provider.server.clone(),
        url: provider.url.clone(),
        weight: provider.weight,
        pin: provider.pin.clone(),
        force_h3,
    }
}

fn parse_route(upstream: &str, pattern: &str) -> Option<ProviderSettings> {
    let upstream = upstream.trim();
    if upstream.is_empty() {
        return None;
    }
    let mut provider = ProviderSettings {
        id: format!("conditional-{pattern}"),
        ..ProviderSettings::default()
    };
    if let Some(rest) = upstream.strip_prefix("h3://") {
        provider.protocol = "DOH3".to_string();
        provider.url = format!("https://{rest}");
    } else if upstream.starts_with("https://") || upstream.starts_with("http://") {
        provider.protocol = "DOH".to_string();
        provider.url = upstream.to_string();
    } else if let Some(rest) = upstream
        .strip_prefix("tls://")
        .or_else(|| upstream.strip_prefix("dot://"))
    {
        provider.protocol = "DOT".to_string();
        provider.server = rest.to_string();
    } else if let Some(rest) = upstream
        .strip_prefix("quic://")
        .or_else(|| upstream.strip_prefix("doq://"))
    {
        provider.protocol = "DOQ".to_string();
        provider.server = rest.to_string();
    } else {
        provider.protocol = "PLAIN".to_string();
        provider.server = upstream.to_string();
    }
    Some(provider)
}

fn provider_host(provider: &ProviderSettings) -> Option<String> {
    let upper = provider.protocol.trim().to_ascii_uppercase();
    match upper.as_str() {
        "DOH" | "DOH3" | "H3" => {
            host_of_url(&provider.url).or_else(|| host_of_target(&provider.server))
        }
        "DOQ" | "QUIC" => host_of_url(&provider.url).or_else(|| host_of_target(&provider.server)),
        _ => host_of_target(&provider.server),
    }
}

fn host_of_url(url: &str) -> Option<String> {
    let rest = url.split_once("://").map(|(_, rest)| rest).unwrap_or(url);
    let authority = rest.split(['/', '?', '#']).next()?;
    let authority = authority.rsplit('@').next()?;
    if let Some(stripped) = authority.strip_prefix('[') {
        let end = stripped.find(']')?;
        return Some(stripped[..end].to_string());
    }
    Some(authority.split(':').next()?.to_string())
}

fn host_of_target(target: &str) -> Option<String> {
    let target = target.trim();
    if target.is_empty() {
        return None;
    }
    if let Some(stripped) = target.strip_prefix('[') {
        let end = stripped.find(']')?;
        return Some(stripped[..end].to_string());
    }
    Some(target.split(':').next()?.to_string())
}

fn clean_suffix(pattern: &str) -> String {
    pattern
        .trim()
        .trim_start_matches('*')
        .trim_matches('.')
        .to_ascii_lowercase()
}

fn query_domain(query: &[u8]) -> Option<String> {
    diting_dns_wire::parse_question(query, 12, false).map(|(question, _)| question.name)
}

fn response_rcode(response: &[u8]) -> Option<i32> {
    diting_dns_wire::parse_response(response).map(|meta| i32::from(meta.rcode))
}

fn event_provider(event: Option<diting_engine::logs::RaceEvent>) -> Option<String> {
    event.and_then(|event| {
        let id = if !event.winner_provider_id.is_empty() {
            event.winner_provider_id
        } else {
            event.selected_provider_id
        };
        (!id.is_empty()).then_some(id)
    })
}
