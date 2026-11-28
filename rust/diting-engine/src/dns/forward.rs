use std::sync::Arc;
use std::time::Instant;

use diting_dns_core::message::{extract, TYPE_AAAA};
use diting_dns_wire::build::ParsedMessage;
use diting_dns_wire::ChainTarget;

use super::{block, rcode_text, row, servfail, ClientMeta};
use crate::engine::Engine;

pub async fn forward(
    engine: &Arc<Engine>,
    query: &[u8],
    domain: &str,
    qtype: u16,
    started: Instant,
    app_name: &str,
    client: &ClientMeta,
) -> Option<Vec<u8>> {
    let cache = engine.cache();

    let dns64_active = qtype == TYPE_AAAA && engine.dns64().is_some();

    if cache.is_enabled() && !dns64_active {
        if let Some(hit) = cache.get(query) {
            if !hit.stale {
                if let Some(reason) = blocked_chain(engine, &hit.chain_targets, qtype, app_name) {
                    return block(engine, query, domain, qtype, &reason, started, app_name, client);
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
                        client,
                    );
                }
                engine.note_query(false);
                engine.log_row(|| {
                    row(domain, false, qtype, started, app_name, client)
                        .resolved_ips(hit.resolved_ips.clone())
                        .cached(true)
                        .cache_hit("HIT")
                        .upstream("cache")
                        .rcode(rcode_text(
                            diting_dns_core::message::extract(&hit.wire)
                                .map(|extracted| extracted.rcode)
                                .unwrap_or(0),
                        ))
                });
                return Some(with_client_id(strip_ipv6_hints(engine, qtype, hit.wire), query));
            }

            if cache.stale_fallback_enabled() {
                if let Some(reason) = blocked_chain(engine, &hit.chain_targets, qtype, app_name) {
                    return block(engine, query, domain, qtype, &reason, started, app_name, client);
                }
                engine.note_query(false);
                engine.log_row(|| {
                    row(domain, false, qtype, started, app_name, client)
                        .resolved_ips(hit.resolved_ips.clone())
                        .cached(true)
                        .cache_hit("STALE")
                        .upstream("cache")
                        .rcode(rcode_text(
                            diting_dns_core::message::extract(&hit.wire)
                                .map(|extracted| extracted.rcode)
                                .unwrap_or(0),
                        ))
                });
                if cache.begin_stale_refresh(query) {
                    let shared = Arc::clone(engine);
                    let query = query.to_vec();
                    let runtime = shared.runtime().handle().clone();
                    runtime.spawn(async move {
                        refresh(shared, query).await;
                    });
                }
                return Some(with_client_id(strip_ipv6_hints(engine, qtype, hit.wire), query));
            }
        }
    }

    if let Some(error) = engine
        .negative_cache()
        .get(query, crate::resolver::now_ns())
    {
        return servfail(engine, query, domain, qtype, started, &error, app_name, client);
    }

    let resolved = super::flight::resolve(engine, query).await;
    match resolved {
        Ok((response, shared, provider)) => {
            engine.negative_cache().remove(query);
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
                        client,
                    )
                }
            };

            if extracted.blocked {
                engine.note_query(true);
                engine.log_row(|| {
                    row(domain, true, qtype, started, app_name, client)
                        .blocked_by("upstream_dns".to_string())
                        .cached(shared)
                        .upstream(provider.clone())
                        .rcode(rcode_text(extracted.rcode))
                });
            } else {
                if let Some(reason) =
                    blocked_chain(engine, &extracted.chain_targets, qtype, app_name)
                {
                    return block(engine, query, domain, qtype, &reason, started, app_name, client);
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
                        client,
                    );
                }
                if let Some((wire, synthesized)) =
                    super::dns64::maybe_synthesize(engine, query, domain, qtype, &extracted.ips)
                        .await
                {
                    engine.note_query(false);
                    engine.log_row(|| {
                        row(domain, false, qtype, started, app_name, client)
                            .resolved_ips(synthesized)
                            .cached(shared)
                            .upstream(provider.clone())
                            .rcode(rcode_text(extracted.rcode))
                    });
                    return Some(with_client_id(wire, query));
                }
                engine.note_query(false);
                engine.log_row(|| {
                    row(domain, false, qtype, started, app_name, client)
                        .resolved_ips(extracted.resolved_ips.clone())
                        .cached(shared)
                        .cache_hit(if shared { "SHARED" } else { "MISS" })
                        .upstream(provider)
                        .rcode(rcode_text(extracted.rcode))
                });
            }

            Some(with_client_id(strip_ipv6_hints(engine, qtype, response), query))
        }
        Err(error) => {
            engine.log_error(&format!("DNS resolve failed standalone {domain}: {error}"));
            engine
                .negative_cache()
                .put(query, &error, crate::resolver::now_ns());
            servfail(engine, query, domain, qtype, started, &error, app_name, client)
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

/// When IPv6 answers are blocked, HTTPS/SVCB records must not hand out
/// ``ipv6hint`` addresses behind the client's back.
fn strip_ipv6_hints(engine: &Engine, qtype: u16, response: Vec<u8>) -> Vec<u8> {
    const TYPE_HTTPS: u16 = 65;
    const TYPE_SVCB: u16 = 64;
    const TYPE_ANY: u16 = 255;
    if !engine.block_ipv6() || !matches!(qtype, TYPE_HTTPS | TYPE_SVCB | TYPE_ANY) {
        return response;
    }
    let Some(mut message) = ParsedMessage::parse(&response) else {
        return response;
    };
    if !message.strip_ipv6_hints() {
        return response;
    }
    message.to_wire().unwrap_or(response)
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

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::{MessageBuilder, RData, ResourceRecord, SvcParam, SvcbRData};
    use diting_dns_wire::{CLASS_IN, TYPE_HTTPS};

    fn https_response() -> Vec<u8> {
        let query = MessageBuilder::query("example.com", TYPE_HTTPS, CLASS_IN)
            .finish()
            .expect("query");
        let svcb = SvcbRData::new(1, ".").push(SvcParam::ipv6hint(&["2001:db8::1"
            .parse()
            .expect("address")]));
        MessageBuilder::reply_to(&query)
            .expect("reply")
            .push_answer(ResourceRecord::new(
                "example.com",
                TYPE_HTTPS,
                CLASS_IN,
                60,
                RData::Https(svcb),
            ))
            .finish()
            .expect("wire")
    }

    #[test]
    fn ipv6_hints_are_only_stripped_when_ipv6_is_blocked() {
        let engine = Engine::new();
        let response = https_response();

        let untouched = strip_ipv6_hints(&engine, TYPE_HTTPS, response.clone());
        assert_eq!(untouched, response);

        engine.set_block_ipv6(true);
        let stripped = strip_ipv6_hints(&engine, TYPE_HTTPS, response);
        let parsed = ParsedMessage::parse(&stripped).expect("parse");
        let RData::Https(svcb) = &parsed.answers[0].rdata else {
            panic!("expected HTTPS");
        };
        assert!(svcb.params.is_empty());
    }
}
