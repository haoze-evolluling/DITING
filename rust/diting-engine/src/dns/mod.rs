//! One DNS query through the standalone pipeline.
//!
//! [`serve`] is `serveDNS` + `standaloneForward` with the Go branches in the same order, because the
//! order is user-visible:
//!
//! 1. the local asset host answers from the kernel's synthesis (`local.pwhs.app`);
//! 2. DDR (`_dns.resolver.arpa`) is refused with NXDOMAIN so Android 13+ and Chrome cannot pick an
//!    encrypted resolver behind the user's back;
//! 3. a rewrite rule answers A/AAAA directly, then a CNAME rewrite resolves the target and answers
//!    with the CNAME plus the target's addresses;
//! 4. `setFilterDNS(false)` skips the whole filtering pipeline — the policy walk included;
//! 5. the policy snapshot decides block or pass;
//! 6. the cache answers when it can, otherwise the upstream does, and the answer is inspected:
//!    a null-block upstream answer is counted as blocked, and a CNAME/HTTPS chain target is
//!    re-evaluated against the policy.
//!
//! Every branch logs exactly one row, and every branch that produces a reply counts exactly one
//! query, which is what `getStats` reports.

pub mod flight;
pub mod forward;

use std::sync::Arc;
use std::time::Instant;

use diting_dns_core::message::{query_info, TYPE_A, TYPE_AAAA};
use diting_dns_core::{reply, ReplyPlan};
use diting_telemetry_core::LogItem;

use crate::engine::Engine;

/// `LocalAssetHost`: the host the MITM side serves the local aesthetic assets from.
pub const LOCAL_ASSET_HOST: &str = "local.pwhs.app";
/// The app name the standalone path reports (`serveDNS`'s default; there is no UID attribution
/// without a TUN and `/proc/net/udp`, so stage 1 keeps the constant).
pub const APP_NAME: &str = "RootProxy";
/// `_dns.resolver.arpa` and its `*.…` children.
const DDR_HOST: &str = "_dns.resolver.arpa";

/// Answers one query with the standalone app name. `None` means "drop it": a query that is not a
/// query, or a kernel that could not build a reply at all. Everything else leaves a log row.
pub async fn serve(engine: &Arc<Engine>, query: &[u8]) -> Option<Vec<u8>> {
    serve_for_app(engine, query, APP_NAME).await
}

/// The TUN variant: the row carries the package the flow belongs to instead of `RootProxy`, which
/// is what `serveDNS(w, r, appOverride, uid)` did for the full-tunnel path.
pub async fn serve_for_app(engine: &Arc<Engine>, query: &[u8], app_name: &str) -> Option<Vec<u8>> {
    let started = Instant::now();
    let info = query_info(query);
    if !info.valid {
        return None;
    }
    let domain = info.name;
    let qtype = info.qtype;

    if domain == LOCAL_ASSET_HOST {
        let plan = reply::local_asset(query)?;
        engine.note_query(false);
        return reply::render(query, &plan);
    }

    if domain == DDR_HOST || domain.ends_with(&format!(".{DDR_HOST}")) {
        let plan = reply::ddr(query)?;
        engine.note_query(true);
        engine.log_row(row(&domain, true, qtype, started, app_name).blocked_by("ddr_blocked"));
        return reply::render(query, &plan);
    }

    if let Some(entry) = engine.rewrites().lookup(&domain) {
        if qtype == TYPE_A || qtype == TYPE_AAAA {
            let ip = if qtype == TYPE_A {
                entry.ip4.clone()
            } else {
                entry.ip6.clone()
            };
            if !ip.is_empty() {
                if let Some(plan) = reply::rewrite_ip(query, &ip) {
                    engine.note_query(false);
                    engine.log_row(
                        row(&domain, false, qtype, started, app_name)
                            .resolved_ips(ip.clone())
                            .blocked_by(format!("rewrite={ip}")),
                    );
                    return reply::render(query, &plan);
                }
            }
        }
        if !entry.cname.is_empty() {
            if let Some(response) = standalone_rewrite(
                engine,
                query,
                &domain,
                &entry.cname,
                qtype,
                started,
                app_name,
            )
            .await
            {
                return Some(response);
            }
        }
    }

    // `setBlockIpv6`: the tunnel carries no usable IPv6, so answer AAAA with an empty NOERROR
    // (NODATA) here instead of handing the client an address it cannot reach and letting the
    // dual-stack retry stall the page/image load (the China Telecom WiFi regression).
    if engine.block_ipv6() && qtype == TYPE_AAAA {
        let plan = reply::block(query, reply::RESPONSE_NO_DATA)?;
        // Filtered, not blocked: an AAAA NODATA is a normal (empty) answer, so it must not inflate
        // the blocked counter the dashboard shows.
        engine.note_query(false);
        engine.log_row(
            row(&domain, false, qtype, started, app_name).blocked_by("ipv6_disabled".to_string()),
        );
        return reply::render(query, &plan);
    }

    if !engine.filter_dns() {
        return forward::forward(engine, query, &domain, qtype, started, app_name).await;
    }

    if engine.policy().is_active() && engine.policy().has_rules() {
        if let Some(verdict) = engine.policy().evaluate(&domain, app_name, qtype) {
            if let Some(reason) = crate::pause::effective_block(
                verdict.blocked,
                &verdict.reason,
                engine.block_paused(),
                engine.allowlist_only(),
            ) {
                return block(engine, query, &domain, qtype, &reason, started, app_name);
            }
        }
    }

    forward::forward(engine, query, &domain, qtype, started, app_name).await
}

/// `standaloneRewrite`: resolve the CNAME target, then answer with the chain. `None` when the caller
/// should keep going (wrong qtype, no answer records, resolution failure), which is the old `false`.
async fn standalone_rewrite(
    engine: &Arc<Engine>,
    query: &[u8],
    domain: &str,
    target: &str,
    qtype: u16,
    started: Instant,
    app_name: &str,
) -> Option<Vec<u8>> {
    if qtype != TYPE_A && qtype != TYPE_AAAA {
        return None;
    }
    let resolver = engine.resolver();
    if resolver.is_empty() {
        return None;
    }

    let target_query = crate::resolver::build_query(target, qtype);
    let response = match resolver.resolve(&target_query).await.0 {
        Ok(response) => response,
        Err(error) => {
            // The old code logged and fell through to the forward path.
            engine.log_error(&format!(
                "Rewrite target resolve failed for {target}: {error}"
            ));
            return None;
        }
    };

    let plan = reply::rewrite_cname(query, target, &response)?;
    if plan.is_not_applicable() {
        return None;
    }
    let wire = reply::render(query, &plan)?;
    engine.note_query(false);
    let resolved = first_address_text(&plan, qtype);
    engine.log_row(
        row(domain, false, qtype, started, app_name)
            .resolved_ips(resolved)
            .blocked_by(format!("rewrite={target}")),
    );
    Some(wire)
}

/// `standaloneBlock`: the configured (or dynamically escalated) block answer.
pub fn block(
    engine: &Arc<Engine>,
    query: &[u8],
    domain: &str,
    qtype: u16,
    blocked_by: &str,
    started: Instant,
    app_name: &str,
) -> Option<Vec<u8>> {
    let mode = engine.effective_block_response(domain);
    let plan = reply::block(query, mode as u8)?;
    let wire = reply::render(query, &plan)?;
    engine.note_query(true);
    engine.log_row(row(domain, true, qtype, started, app_name).blocked_by(blocked_by.to_string()));
    Some(wire)
}

/// The SERVFAIL answer used on the error paths; the row is pushed here so no caller can forget it.
pub fn servfail(
    engine: &Arc<Engine>,
    query: &[u8],
    domain: &str,
    qtype: u16,
    started: Instant,
    error: &str,
    app_name: &str,
) -> Option<Vec<u8>> {
    let plan = reply::servfail(query)?;
    let wire = reply::render(query, &plan)?;
    engine.note_query(false);
    engine.log_row(row(domain, false, qtype, started, app_name).error_message(error.to_string()));
    Some(wire)
}

/// A log row builder, so every branch spells the fields once and the same way.
fn row(domain: &str, blocked: bool, qtype: u16, started: Instant, app_name: &str) -> LogRow {
    LogRow {
        domain: domain.to_string(),
        blocked,
        query_type: qtype,
        response_time_ms: started.elapsed().as_millis() as i64,
        app_name: app_name.to_string(),
        resolved_ips: String::new(),
        blocked_by: String::new(),
        error_message: String::new(),
        cached: false,
        ttl: 0,
    }
}

/// The row under construction; every field is set exactly once before it is pushed.
pub struct LogRow {
    domain: String,
    blocked: bool,
    query_type: u16,
    response_time_ms: i64,
    app_name: String,
    resolved_ips: String,
    blocked_by: String,
    error_message: String,
    cached: bool,
    ttl: i64,
}

impl LogRow {
    pub fn resolved_ips(mut self, ips: impl Into<String>) -> Self {
        self.resolved_ips = ips.into();
        self
    }

    pub fn blocked_by(mut self, reason: impl Into<String>) -> Self {
        self.blocked_by = reason.into();
        self
    }

    pub fn error_message(mut self, message: impl Into<String>) -> Self {
        self.error_message = message.into();
        self
    }

    pub fn cached(mut self, cached: bool) -> Self {
        self.cached = cached;
        self
    }

    pub fn ttl(mut self, ttl: i64) -> Self {
        self.ttl = ttl;
        self
    }

    /// An engine-level error line, shaped like a failed query so the log viewer renders it.
    pub fn error_row(message: &str, timestamp_ms: i64) -> LogItem {
        LogItem {
            domain: String::new(),
            blocked: false,
            query_type: 0,
            response_time_ms: 0,
            app_name: String::new(),
            resolved_ips: String::new(),
            blocked_by: String::new(),
            error_message: message.to_string(),
            cached: false,
            timestamp_ms,
            ttl: 0,
        }
    }

    /// Stamps the push time, which is when the UI sees the row.
    pub fn build(self, timestamp_ms: i64) -> LogItem {
        LogItem {
            domain: self.domain,
            blocked: self.blocked,
            query_type: self.query_type as i32,
            response_time_ms: self.response_time_ms,
            app_name: self.app_name,
            resolved_ips: self.resolved_ips,
            blocked_by: self.blocked_by,
            error_message: self.error_message,
            cached: self.cached,
            timestamp_ms,
            ttl: self.ttl,
        }
    }
}

/// `firstAddressText`: the first A/AAAA rdata of a plan, printed the way `net.IP.String()` does.
fn first_address_text(plan: &ReplyPlan, qtype: u16) -> String {
    for record in &plan.answers {
        if record.rrtype != qtype {
            continue;
        }
        match record.rdata.len() {
            4 => return diting_dns_wire::format_ipv4(&record.rdata),
            16 => return diting_dns_wire::format_ipv6(&record.rdata),
            _ => {}
        }
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// `setBlockIpv6` turns AAAA into a successful, answer-less reply so the client stops asking
    /// (and stops trying to reach an IPv6 address the tunnel cannot carry).
    #[test]
    fn aaaa_is_nodata_when_ipv6_is_blocked() {
        let engine = Arc::new(Engine::new());
        engine.set_block_ipv6(true);
        let query = crate::resolver::build_query("example.com", TYPE_AAAA);

        let response = engine
            .runtime()
            .block_on(serve_for_app(&engine, &query, "test"))
            .expect("an AAAA query must still get a reply");

        assert_eq!(response[3] & 0x0f, 0, "rcode must be NOERROR");
        assert_eq!(
            u16::from_be_bytes([response[6], response[7]]),
            0,
            "NODATA carries no answer records"
        );
    }

    /// The policy walk must see the flow's app; passing a constant would make app-scoped rules
    /// (`appRules` / `app=` special rules) match every app or none of them.
    #[test]
    fn app_scoped_block_uses_the_flow_app_name() {
        let engine = Arc::new(Engine::new());
        engine.set_filter_dns(true);
        let error = engine.apply_rule_snapshot(
            r#"{"filterEnabled":true,"globalBlock":[],"appRules":{"com.example.app":{"block":["blocked.test"]}}}"#,
        );
        assert!(error.is_empty(), "{error}");
        let query = crate::resolver::build_query("blocked.test", TYPE_A);

        engine
            .runtime()
            .block_on(serve_for_app(&engine, &query, "com.example.app"))
            .expect("a blocked query answers without an upstream");
        assert_eq!(engine.blocked_queries(), 1, "the rule applies to its app");

        // Another app falls through to forwarding; with no upstream it turns into SERVFAIL, but
        // it must not be counted as blocked.
        engine
            .runtime()
            .block_on(serve_for_app(&engine, &query, "com.other"))
            .expect("a forwarded query still answers");
        assert_eq!(engine.blocked_queries(), 1, "the rule is app-scoped");
    }
}
