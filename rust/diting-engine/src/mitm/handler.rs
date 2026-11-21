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

pub const PORT_HTTP: u16 = 80;
pub const PORT_HTTPS: u16 = 443;

pub async fn handle_tcp(
    engine: Arc<Engine>,
    events: Arc<Events>,
    counters: Arc<TunnelCounters>,
    key: TcpKey,
    context: FlowContext,
    rx: mpsc::Receiver<Inbound>,
) {
    let Some(mitm) = engine.mitm_state().session() else {
        let credit = Arc::new(Semaphore::new(MAX_PENDING_WRITE));
        crate::tunnel::relay::relay_tcp(
            Arc::clone(&engine),
            events,
            counters,
            key,
            context.uid,
            rx,
            credit,
            None,
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
            relay_peeked(&engine, &events, &counters, key, &context, stream).await;
            return;
        }
    };

    let hostname = hostname_for(&sniffed.host, key);
    if hostname.is_empty() {
        relay_peeked(&engine, &events, &counters, key, &context, stream).await;
        return;
    }

    if local::is_asset_host(&hostname) {
        let mode = LocalMode::Assets {
            engine: Arc::clone(&engine),
        };
        serve_local(&mitm, stream, &hostname, protocol, mode).await;
        return;
    }

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

    let upstream = match dial_upstream(&engine, &counters, key, context.uid).await {
        Ok(upstream) => upstream,
        Err(_) => {
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

fn refusal(facts: &crate::mitm::upstream::UpstreamFacts) -> Option<&'static str> {
    refusal_reason(facts.client_cert_requested, facts.extended_validation)
}

fn refusal_reason(client_cert_requested: bool, extended_validation: bool) -> Option<&'static str> {
    if client_cert_requested {
        return Some("client-certificate (mTLS) request");
    }
    if extended_validation {
        return Some("EV certificate");
    }
    None
}

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

fn hostname_for(sniffed_host: &[u8], key: TcpKey) -> String {
    let text = String::from_utf8_lossy(sniffed_host).to_string();
    let text = diting_go_compat::text::go_lower(diting_go_compat::text::go_trim_space(&text));
    if !text.is_empty() {
        return text.into_owned();
    }
    diting_go_compat::text::go_lower(&netstack::address_text(key.local.addr)).into_owned()
}

fn rewrite_target(engine: &Engine, host: &str) -> Option<String> {
    let entry = engine.rewrites().lookup(host)?;
    (!entry.cname.is_empty()).then_some(entry.cname)
}

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
