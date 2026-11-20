use std::sync::Arc;

use diting_desktop_core::querylog::{
    QueryLog, Record, STATUS_ALLOWED, STATUS_BLOCKED, STATUS_CACHED, STATUS_ERROR, STATUS_STALE,
};
use diting_desktop_dns::context::DnsContext;
use diting_desktop_dns::stages::metrics::QueryObserver;

pub struct ServerQueryObserver {
    querylog: Arc<QueryLog>,
}

impl ServerQueryObserver {
    pub fn new(querylog: Arc<QueryLog>) -> Self {
        Self { querylog }
    }
}

fn attribute(ctx: &DnsContext, key: &str) -> String {
    ctx.get(key).unwrap_or("").to_string()
}

fn attribute_bool(ctx: &DnsContext, key: &str) -> bool {
    matches!(ctx.get(key), Some("true" | "1"))
}

fn rcode_name(ctx: &DnsContext) -> String {
    let Some(response) = ctx.response.as_ref() else {
        return String::new();
    };
    if response.len() < 4 {
        return String::new();
    }
    match response[3] & 0x0f {
        0 => "NOERROR",
        1 => "FORMERR",
        2 => "SERVFAIL",
        3 => "NXDOMAIN",
        4 => "NOTIMP",
        5 => "REFUSED",
        _ => "OTHER",
    }
    .to_string()
}

fn now_ms() -> i64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_millis() as i64)
        .unwrap_or(0)
}

impl QueryObserver for ServerQueryObserver {
    fn observe(&self, ctx: &DnsContext) {
        let cache_hit = attribute(ctx, "cache_hit");
        let blocked = attribute_bool(ctx, "filter_blocked")
            || attribute_bool(ctx, "rebinding_blocked")
            || attribute_bool(ctx, "access_blocked")
            || attribute_bool(ctx, "ratelimit_blocked")
            || attribute_bool(ctx, "unqualified_blocked");
        let mut filter_rule = attribute(ctx, "filter_rule");
        if filter_rule.is_empty() {
            filter_rule = if attribute_bool(ctx, "rebinding_blocked") {
                "REBIND_PROTECTION"
            } else if attribute_bool(ctx, "access_blocked") {
                "CLIENT_ACCESS_CONTROL"
            } else if attribute_bool(ctx, "ratelimit_blocked") {
                "RATE_LIMIT_EXCEEDED"
            } else if attribute_bool(ctx, "unqualified_blocked") {
                "BLOCK_UNQUALIFIED"
            } else {
                ""
            }
            .to_string();
        }
        let rcode = rcode_name(ctx);
        let error = ctx.error.clone().unwrap_or_default();
        let status = if !error.is_empty() {
            STATUS_ERROR
        } else if blocked {
            STATUS_BLOCKED
        } else if cache_hit == "stale" {
            STATUS_STALE
        } else if !cache_hit.is_empty() {
            STATUS_CACHED
        } else {
            STATUS_ALLOWED
        };

        self.querylog.record(Record {
            timestamp: now_ms(),
            domain: ctx.question.name.trim_end_matches('.').to_string(),
            qtype: diting_desktop_core::cache::qtype_name(ctx.question.qtype),
            client_ip: ctx
                .client
                .map(|address| address.ip().to_string())
                .unwrap_or_default(),
            client_name: ctx.client_name.clone(),
            duration_ms: ctx.elapsed_ms(),
            rcode,
            status: status.to_string(),
            cached: !cache_hit.is_empty(),
            ttl: ctx
                .response
                .as_ref()
                .and_then(|wire| diting_dns_wire::parse_response(wire))
                .and_then(|meta| meta.min_ttl),
            cache_hit,
            blocked,
            filter_rule,
            filter_reason: attribute(ctx, "filter_reason"),
            protocol: ctx.transport.as_str().to_string(),
            upstream_provider: attribute(ctx, "upstream_provider"),
            error,
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_desktop_core::querylog::{Config, SearchQuery};
    use diting_desktop_dns::context::Transport;
    use std::net::SocketAddr;

    fn query(name: &str) -> Vec<u8> {
        diting_dns_wire::build::MessageBuilder::query(name, 1, 1)
            .finish()
            .unwrap()
    }

    #[test]
    fn observer_records_client_upstream_and_status() {
        let querylog = Arc::new(QueryLog::new(Config {
            file_enabled: false,
            ..Config::default()
        }));
        let observer = ServerQueryObserver::new(Arc::clone(&querylog));
        let mut ctx = DnsContext::new(
            query("ads.example.com"),
            Some(SocketAddr::from(([192, 168, 1, 9], 4242))),
            Transport::Udp,
        )
        .unwrap();
        ctx.set("filter_blocked", "true");
        ctx.set("filter_rule", "||ads.example.com^");
        ctx.set("upstream_provider", "AliDNS");
        ctx.reply_with_rcode(0);
        observer.observe(&ctx);

        let result = querylog.search(SearchQuery {
            limit: 10,
            ..SearchQuery::default()
        });
        assert_eq!(result.total, 1);
        assert_eq!(result.entries[0].client_ip, "192.168.1.9");
        assert_eq!(result.entries[0].upstream_provider, "AliDNS");
        assert_eq!(result.entries[0].status, STATUS_BLOCKED);
    }
}
