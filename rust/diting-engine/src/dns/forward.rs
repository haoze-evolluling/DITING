//! Cache → single flight → upstream, and the answer inspection every forwarding path runs.
//!
//! The shape is `standaloneForward`'s:
//!
//! * a fresh cache hit answers immediately (`cached=true` in the log);
//! * a stale hit inside the stale window answers too, and one background refresh per entry is
//!   started so a burst of stale hits cannot spawn a resolver call each;
//! * otherwise the query goes upstream through the single-flight coalescer, which stores what it
//!   resolved (`dnsCache.singleFlight`);
//! * the answer is inspected: a null-block answer counts as blocked (`upstream_dns`), and a chain
//!   target is re-evaluated against the policy before the answer is handed over.

use std::sync::Arc;
use std::time::Instant;

use diting_dns_core::message::extract;
use diting_dns_wire::ChainTarget;

use super::{block, row, servfail};
use crate::engine::Engine;

/// One forwarding pass for `domain`/`qtype`.
pub async fn forward(
    engine: &Arc<Engine>,
    query: &[u8],
    domain: &str,
    qtype: u16,
    started: Instant,
    app_name: &str,
) -> Option<Vec<u8>> {
    let cache = engine.cache();

    if cache.is_enabled() {
        if let Some(hit) = cache.get(query) {
            if !hit.stale {
                if let Some(reason) = blocked_chain(engine, &hit.chain_targets, qtype, app_name) {
                    return block(engine, query, domain, qtype, &reason, started, app_name);
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

/// The policy re-evaluation of a CNAME/SVCB chain target (`checkResponseChainTargets`).
///
/// Every target is evaluated as the query's own type, and the first block wins: a block page served
/// through a CNAME is still a block.
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
    for target in targets {
        if let Some(verdict) = engine.policy().evaluate(&target.domain, app_name, qtype) {
            if verdict.blocked {
                return Some(verdict.reason);
            }
        }
    }
    None
}

/// The client gets the upstream wire, not a re-packed copy: only the transaction id has to follow
/// the client's question. A shared single-flight answer carries the leader's id, which is why this
/// runs on every forwarded answer.
fn with_client_id(mut response: Vec<u8>, query: &[u8]) -> Vec<u8> {
    if response.len() >= 2 && query.len() >= 2 {
        response[0] = query[0];
        response[1] = query[1];
    }
    response
}

/// One background refresh of a stale entry: resolve, store, release the claim.
///
/// The claim is released in every outcome (a failed refresh must not block the next one), which is
/// `defer dnsCache.endStaleRefresh(raw)` in the old code.
pub async fn refresh(engine: Arc<Engine>, query: Vec<u8>) {
    let cache = engine.cache();
    let resolver = engine.resolver();
    if let Ok(response) = resolver.resolve(&query).await.0 {
        cache.put(&query, &response);
    }
    cache.end_stale_refresh(&query);
}
