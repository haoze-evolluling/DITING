use std::sync::Arc;
use std::time::Instant;

use diting_dns_core::message::{extract, TYPE_AAAA};
use diting_dns_wire::ChainTarget;

use super::{block, row, servfail};
use crate::engine::Engine;

pub async fn forward(
    engine: &Arc<Engine>,
    query: &[u8],
    domain: &str,
    qtype: u16,
    started: Instant,
    app_name: &str,
) -> Option<Vec<u8>> {
    let cache = engine.cache();

    let dns64_active = qtype == TYPE_AAAA && engine.dns64().is_some();

    if cache.is_enabled() && !dns64_active {
        if let Some(hit) = cache.get(query) {
            if !hit.stale {
                if let Some(reason) = blocked_chain(engine, &hit.chain_targets, qtype, app_name) {
                    return block(engine, query, domain, qtype, &reason, started, app_name);
                }
                if engine.rebinding_protection()
                    && crate::privacy::any_private(hit.resolved_ips.split(',').map(str::trim))
                {
                    return block(
                        engine,
                        query,
                        domain,
                        qtype,
                        "rebinding_protected",
                        started,
                        app_name,
                    );
                }
                engine.note_query(false);
                engine.log_row(
                    row(domain, false, qtype, started, app_name)
                        .resolved_ips(hit.resolved_ips.clone())
                        .cached(true),
                );
                return Some(hit.wire);
            }

            if cache.stale_fallback_enabled() {
                if let Some(reason) = blocked_chain(engine, &hit.chain_targets, qtype, app_name) {
                    return block(engine, query, domain, qtype, &reason, started, app_name);
                }
                engine.note_query(false);
                engine.log_row(
                    row(domain, false, qtype, started, app_name)
                        .resolved_ips(hit.resolved_ips.clone())
                        .cached(true),
                );
                if cache.begin_stale_refresh(query) {
                    let shared = Arc::clone(engine);
                    let query = query.to_vec();
                    let runtime = shared.runtime().handle().clone();
                    runtime.spawn(async move {
                        refresh(shared, query).await;
                    });
                }
                return Some(hit.wire);
            }
        }
    }

    let resolved = super::flight::resolve(engine, query).await;
    match resolved {
        Ok((response, shared)) => {
            let extracted = match extract(&response) {
                Some(extracted) => extracted,
                None => {
                    return servfail(
                        engine,
                        query,
                        domain,
                        qtype,
                        started,
                        "DNS answer extract failed",
                        app_name,
                    )
                }
            };

            if extracted.blocked {
                engine.note_query(true);
                engine.log_row(
                    row(domain, true, qtype, started, app_name)
                        .blocked_by("upstream_dns".to_string())
                        .cached(shared),
                );
            } else {
                if let Some(reason) =
                    blocked_chain(engine, &extracted.chain_targets, qtype, app_name)
                {
                    return block(engine, query, domain, qtype, &reason, started, app_name);
                }
                if engine.rebinding_protection()
                    && crate::privacy::any_private(extracted.ips.iter().map(String::as_str))
                {
                    return block(
                        engine,
                        query,
                        domain,
                        qtype,
                        "rebinding_protected",
                        started,
                        app_name,
                    );
                }
                if let Some((wire, synthesized)) =
                    super::dns64::maybe_synthesize(engine, query, domain, qtype, &extracted.ips)
                        .await
                {
                    engine.note_query(false);
                    engine.log_row(
                        row(domain, false, qtype, started, app_name)
                            .resolved_ips(synthesized)
                            .cached(shared),
                    );
                    return Some(with_client_id(wire, query));
                }
                engine.note_query(false);
                engine.log_row(
                    row(domain, false, qtype, started, app_name)
                        .resolved_ips(extracted.resolved_ips.clone())
                        .cached(shared),
                );
            }

            Some(with_client_id(response, query))
        }
        Err(error) => {
            engine.log_error(&format!("DNS resolve failed standalone {domain}: {error}"));
            servfail(engine, query, domain, qtype, started, &error, app_name)
        }
    }
}

fn blocked_chain(
    engine: &Arc<Engine>,
    targets: &[ChainTarget],
    qtype: u16,
    app_name: &str,
) -> Option<String> {
    if !engine.filter_dns() || targets.is_empty() {
        return None;
    }
    if !engine.policy().is_active() || !engine.policy().has_rules() {
        return None;
    }
    let plan = diting_response_core::plan_strs(
        targets.iter().map(|target| target.domain.as_str()),
        diting_response_core::DEFAULT_MAX_DEPTH,
    );
    for domain in &plan.targets {
        if let Some(verdict) = engine.policy().evaluate(domain, app_name, qtype) {
            if verdict.blocked {
                return Some(verdict.reason);
            }
        }
    }
    None
}

fn with_client_id(mut response: Vec<u8>, query: &[u8]) -> Vec<u8> {
    if response.len() >= 2 && query.len() >= 2 {
        response[0] = query[0];
        response[1] = query[1];
    }
    response
}

pub async fn refresh(engine: Arc<Engine>, query: Vec<u8>) {
    let _claim = RefreshClaim {
        engine: Arc::clone(&engine),
        query: query.clone(),
    };
    let cache = engine.cache();
    let resolver = engine.resolver();
    if let Ok(response) = resolver.resolve(&query).await.0 {
        cache.put(&query, &response);
    }
}

struct RefreshClaim {
    engine: Arc<Engine>,
    query: Vec<u8>,
}

impl Drop for RefreshClaim {
    fn drop(&mut self) {
        self.engine.cache().end_stale_refresh(&self.query);
    }
}
