//! The interception pipeline: peek, classify, then route one TCP flow to TLS, HTTP or passthrough.
//!
//! This is `mitm_handler.go` after stage 3 already applied the gate:
//!
//! ```text
//! gate (diting-gate-core, MODE_MITM_TCP) → Intercept
//!   1. peek the first bytes                  (peekFlow, 4 KiB, 10 s)
//!   2. classify                              (diting-sniffer-core: TLS SNI / HTTP Host / neither)
//!   3. local asset host   → answer locally    (local.rs, TLS terminated with a minted leaf)
//!   4. CNAME rewrite      → 302 to the target (local.rs)
//!   5. TLS + blocked host → drop              (diting-policy-core, `https_domain_rule`)
//!   6. filter refuses     → passthrough       (diting-mitm-core: blacklist, bypass, bank heuristics)
//!   7. TLS  → terminate, handshake upstream, relay HTTP/1.1
//!   8. HTTP → dial, relay HTTP/1.1
//! ```
//!
//! Two orderings are load-bearing and are kept from Go:
//!
//! * **the client handshake comes first.** A client that pins its certificate aborts in the first
//!   flight, so the upstream radio is never touched; only a client that accepted the minted leaf pays
//!   for the upstream connection.
//! * **passthrough is decided before the upstream dial.** A host the filter protects is relayed as
//!   opaque bytes, so a banking app sees the real certificate chain.
//!
//! Failure logging is unchanged: `handshake_failed` / `client_tls` records a failure streak (three in
//! ten minutes blacklists the host, two when the client rejected our certificate),
//! `upstream_failed` / `upstream_tls` is reported once, and an EV or mTLS upstream is blacklisted with
//! its reason.

use std::sync::Arc;

use tokio::net::TcpStream;
use tokio::sync::{mpsc, Semaphore};

use crate::engine::Engine;
use crate::mitm::filter;
use crate::mitm::http::{Protocol, Relay};
use crate::mitm::local::{self, LocalMode};
use crate::mitm::stream::ClientStream;
use crate::mitm::{now_ms, Mitm};
use crate::netstack::{self, TcpKey};
use crate::tunnel::dnsflow::Inbound;
use crate::tunnel::gate::FlowContext;
use crate::tunnel::queue::{Event, Events};
use crate::tunnel::stats::TunnelCounters;
use crate::tunnel::writeback::MAX_PENDING_WRITE;
use diting_sniffer_core::Kind;

/// `PORT_HTTP`: the plaintext port the MITM gate intercepts.
pub const PORT_HTTP: u16 = 80;
/// `PORT_HTTPS`.
pub const PORT_HTTPS: u16 = 443;

/// One intercepted TCP flow, from the first peeked byte to the last relayed one.
pub async fn handle_tcp(
    engine: Arc<Engine>,
    events: Arc<Events>,
    counters: Arc<TunnelCounters>,
    key: TcpKey,
    context: FlowContext,
    rx: mpsc::Receiver<Inbound>,
) {
    let Some(mitm) = engine.mitm_state().session() else {
        // `StopStackMitm` landed between the gate and this task: relay it opaquely, which is what an
        // uninstalled handler would have done. The reservation is the same per-flow write budget a
        // normal relay uses, so a large response still gets backpressure rather than a reset.
        let credit = Arc::new(Semaphore::new(MAX_PENDING_WRITE));
        crate::tunnel::relay::relay_tcp(
            Arc::clone(&engine),
            events,
            counters,
            key,
            context.uid,
            rx,
            credit,
        )
        .await;
        return;
    };

    let mut stream = ClientStream::new(
        Arc::clone(&engine),
        Arc::clone(&events),
        key,
        context.uid,
        rx,
    );
    let peeked = stream.peek(crate::mitm::stream::PEEK_TIMEOUT).await;
    if peeked.is_empty() {
        stream.close_write();
        return;
    }

    let sniffed = diting_sniffer_core::classify(&peeked);
    let protocol = match sniffed.kind {
        Kind::Tls => Protocol::Https,
        Kind::Http => Protocol::Http,
        Kind::Unknown => {
            // Neither TLS nor HTTP: hand the bytes to the passthrough relay untouched.
            relay_peeked(&engine, &events, &counters, key, &context, stream).await;
            return;
        }
    };

    let hostname = hostname_for(&sniffed.host, key);
    if hostname.is_empty() {
        relay_peeked(&engine, &events, &counters, key, &context, stream).await;
        return;
    }

    // 3. The embedded stylesheet origin answers without a network round trip.
    if local::is_asset_host(&hostname) {
        let mode = LocalMode::Assets {
            engine: Arc::clone(&engine),
        };
        serve_local(&mitm, stream, &hostname, protocol, mode).await;
        return;
    }

    // 4. A rewritten CNAME becomes a 302 to the real origin.
    if let Some(target) = rewrite_target(&engine, &hostname) {
        let mode = LocalMode::Redirect {
            target,
            engine: Arc::clone(&engine),
            package: context.app.clone(),
            protocol,
        };
        serve_local(&mitm, stream, &hostname, protocol, mode).await;
        return;
    }

    // 5. A blocked host is dropped before any TLS work, like Go's pre-handshake check.
    if protocol.is_https() {
        if let Some(reason) = blocked_reason(&engine, &hostname, &context.app) {
            engine.mitm_state().settings().log_http(
                &context.app,
                &hostname,
                protocol.name(),
                "blocked",
                &reason,
            );
            stream.close_write();
            return;
        }
    }

    // 6. The filter is the last word: blacklists, bypass patterns and the banking heuristics.
    if !mitm.filter().allows_interception(&hostname, now_ms()) {
        engine.mitm_state().settings().log_http(
            &context.app,
            &hostname,
            protocol.name(),
            "passthrough",
            "passthrough",
        );
        relay_peeked(&engine, &events, &counters, key, &context, stream).await;
        return;
    }

    // 7/8. Intercept.
    let upstream = match dial_upstream(&engine, &counters, key, context.uid).await {
        Ok(upstream) => upstream,
        Err(_) => {
            // Go's `mitm_relay.go` logged the dial failure into the HTTP log before giving up:
            // `upstream_tls` for a TLS flow, `upstream_dial` for plain HTTP.
            engine.mitm_state().settings().log_http(
                &context.app,
                &hostname,
                protocol.name(),
                "upstream_failed",
                if protocol.is_https() {
                    "upstream_tls"
                } else {
                    "upstream_dial"
                },
            );
            stream.abort();
            return;
        }
    };

    if protocol.is_https() {
        intercept_tls(
            engine, events, key, context, stream, mitm, upstream, hostname,
        )
        .await;
    } else {
        Relay::new(
            Arc::clone(&engine),
            hostname.clone(),
            Protocol::Http,
            context.app.clone(),
        )
        .serve(stream, upstream)
        .await
        .ok();
        events.push_command(Event::CloseWrite(key));
    }
}

/// The client handshake, then the upstream handshake, then the HTTP relay.
#[allow(clippy::too_many_arguments)]
async fn intercept_tls(
    engine: Arc<Engine>,
    events: Arc<Events>,
    key: TcpKey,
    context: FlowContext,
    stream: ClientStream,
    mitm: Arc<Mitm>,
    upstream: TcpStream,
    hostname: String,
) {
    let config = mitm.certs().server_config(Some(&hostname));
    let client = match tokio_rustls::TlsAcceptor::from(config).accept(stream).await {
        Ok(client) => client,
        Err(error) => {
            // A pinning client aborts here: the failure streak is what blacklists the host.
            record_failure(&engine, &mitm, &hostname, &error.to_string());
            engine.mitm_state().settings().log_http(
                &context.app,
                &hostname,
                Protocol::Https.name(),
                "handshake_failed",
                "client_tls",
            );
            return;
        }
    };

    let facts = match mitm.upstream().connect(&hostname, upstream).await {
        Ok(facts) => facts,
        Err(error) => {
            engine.log_error(&format!("MITM: upstream TLS to {hostname} failed: {error}"));
            engine.mitm_state().settings().log_http(
                &context.app,
                &hostname,
                Protocol::Https.name(),
                "upstream_failed",
                "upstream_tls",
            );
            return;
        }
    };

    if let Some(reason) = refusal(&facts) {
        engine.log_error(&format!(
            "MITM: not filtering '{hostname}' — {reason}; recorded for future passthrough"
        ));
        blacklist(&engine, &mitm, &hostname, reason);
        engine.mitm_state().settings().log_http(
            &context.app,
            &hostname,
            Protocol::Https.name(),
            "handshake_failed",
            reason,
        );
        return;
    }

    Relay::new(
        Arc::clone(&engine),
        hostname.clone(),
        Protocol::Https,
        context.app.clone(),
    )
    .serve(client, facts.stream)
    .await
    .ok();
    events.push_command(Event::CloseWrite(key));
}

/// Why the flow must not be intercepted, or `None` when it may be.
fn refusal(facts: &crate::mitm::upstream::UpstreamFacts) -> Option<&'static str> {
    refusal_reason(facts.client_cert_requested, facts.extended_validation)
}

/// The Go rule: a `CertificateRequest` or an EV policy OID means "leave this one alone".
fn refusal_reason(client_cert_requested: bool, extended_validation: bool) -> Option<&'static str> {
    if client_cert_requested {
        return Some("client-certificate (mTLS) request");
    }
    if extended_validation {
        return Some("EV certificate");
    }
    None
}

/// The local-only flows (assets, redirect) still need the client side terminated when it is TLS.
async fn serve_local(
    mitm: &Arc<Mitm>,
    stream: ClientStream,
    hostname: &str,
    protocol: Protocol,
    mode: LocalMode,
) {
    if protocol.is_https() {
        let config = mitm.certs().server_config(Some(hostname));
        if let Ok(client) = tokio_rustls::TlsAcceptor::from(config).accept(stream).await {
            local::serve_local(client, mode).await.ok();
        }
        return;
    }
    local::serve_local(stream, mode).await.ok();
}

/// `dialUpstream`: the flow's original destination, through the outbound transport.
async fn dial_upstream(
    engine: &Arc<Engine>,
    counters: &Arc<TunnelCounters>,
    key: TcpKey,
    uid: i32,
) -> Result<TcpStream, String> {
    let target = netstack::socket_addr(key.local);
    let outbound = engine.outbound();
    let route = outbound.route_for(uid);
    match outbound.dial_tcp(route, target).await {
        Ok(stream) => Ok(stream),
        Err(error) => {
            counters
                .relay_unavailable
                .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            engine.log_error(&format!(
                "[TcpStack] upstream dial {target} failed: {error}"
            ));
            Err(error)
        }
    }
}

/// The passthrough relay for a flow this handler will not decrypt.
async fn relay_peeked(
    engine: &Arc<Engine>,
    events: &Arc<Events>,
    counters: &Arc<TunnelCounters>,
    key: TcpKey,
    context: &FlowContext,
    stream: ClientStream,
) {
    let upstream = match dial_upstream(engine, counters, key, context.uid).await {
        Ok(upstream) => upstream,
        Err(_) => {
            stream.abort();
            return;
        }
    };
    let (mut upstream_read, mut upstream_write) = upstream.into_split();
    let (mut client_read, mut client_write) = tokio::io::split(stream);
    let upstream_leg = async {
        let copied = tokio::io::copy(&mut client_read, &mut upstream_write).await;
        let _ = tokio::io::AsyncWriteExt::shutdown(&mut upstream_write).await;
        copied.is_ok()
    };
    let client_leg = async {
        let copied = tokio::io::copy(&mut upstream_read, &mut client_write).await;
        let _ = tokio::io::AsyncWriteExt::shutdown(&mut client_write).await;
        copied.is_ok()
    };
    let (forwarded, _) = tokio::join!(upstream_leg, client_leg);
    let _ = forwarded;
    events.push_command(Event::CloseWrite(key));
}

fn record_failure(engine: &Arc<Engine>, mitm: &Arc<Mitm>, host: &str, error: &str) {
    let report = mitm.filter().record_failure(host, error, now_ms());
    for line in filter::failure_lines(&report, error) {
        engine.log_error(&line);
    }
}

fn blacklist(engine: &Arc<Engine>, mitm: &Arc<Mitm>, host: &str, reason: &str) {
    if let Some(report) = mitm.filter().blacklist(host, reason, now_ms()) {
        for line in filter::blacklist_lines(&report) {
            engine.log_error(&line);
        }
    }
}

/// The SNI, the HTTP `Host`, or the destination address: `logHTTPEvent`'s authority column.
fn hostname_for(sniffed_host: &[u8], key: TcpKey) -> String {
    let text = String::from_utf8_lossy(sniffed_host).to_string();
    let text = diting_go_compat::text::go_lower(diting_go_compat::text::go_trim_space(&text));
    if !text.is_empty() {
        return text.into_owned();
    }
    diting_go_compat::text::go_lower(&netstack::address_text(key.local.addr)).into_owned()
}

/// `rewriteCNAME`: a hostname rewrite target, or nothing.
fn rewrite_target(engine: &Engine, host: &str) -> Option<String> {
    let entry = engine.rewrites().lookup(host)?;
    (!entry.cname.is_empty()).then_some(entry.cname)
}

/// `checkDomainBlockedAndReason`, with Go's `https_domain_rule` fallback for an empty reason.
fn blocked_reason(engine: &Engine, host: &str, package: &str) -> Option<String> {
    let reason = crate::mitm::http::domain_blocked(engine, host, package)?;
    Some(if reason.is_empty() {
        "https_domain_rule".to_string()
    } else {
        reason
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_refusal_reasons_are_the_go_strings() {
        assert_eq!(
            refusal_reason(true, false),
            Some("client-certificate (mTLS) request")
        );
        assert_eq!(refusal_reason(false, true), Some("EV certificate"));
        // mTLS wins when both are true, exactly like the Go branch order.
        assert_eq!(
            refusal_reason(true, true),
            Some("client-certificate (mTLS) request")
        );
        assert_eq!(refusal_reason(false, false), None);
    }

    #[test]
    fn the_intercepted_ports_are_80_and_443() {
        assert_eq!(PORT_HTTP, 80);
        assert_eq!(PORT_HTTPS, 443);
    }
}
