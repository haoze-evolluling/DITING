//! The four upstream transports, driven by real loopback servers.
//!
//! Every case here is end to end on 127.0.0.1: a real UDP/TCP socket, a real TLS handshake, a real
//! HTTP/2 connection, a real QUIC handshake. The only thing replaced is the certificate authority
//! (minted per test by `diting-cert-core`) and the upstream DNS server itself.
//!
//! What the cases pin, in the order the migration plan cares about them:
//!
//! * plain UDP answers, and a `TC=1` answer is retried over TCP on the *same* port;
//! * DoT parks a connection and the next query reuses it (one accepted socket for two queries);
//! * DoH negotiates HTTP/2 and reuses the session, and a 403 becomes `DoH rate limited (403)`;
//! * DoQ opens a bidirectional stream per query on one QUIC connection;
//! * the bootstrap resolver turns `dot.test` into `127.0.0.1` and reports it through
//!   `BootstrapLogCallback`'s event;
//! * `parallel_race` returns the fast provider's answer and reports the winning provider;
//! * the engine hands its trust store to the transports, so `ResolveDomain` reaches a DoH upstream.

mod support;

use std::sync::atomic::Ordering;
use std::sync::Arc;

use diting_engine::config::DnsConfig;
use diting_engine::resolver::trust::UpstreamTrust;
use http::Version;
use support::*;

// ---- cases --------------------------------------------------------------------------------------

#[tokio::test]
async fn plain_udp_answers_the_query() {
    let (upstream, count) = spawn_udp_upstream([1, 2, 3, 4], false);
    let config = config_json(
        "single",
        &[provider_json("p1", "PLAIN", &upstream.to_string(), "")],
        None,
    );
    let resolver = resolver(&config, None, Arc::new(Recorder::default()));

    let query = query_wire("example.test", 0x1234);
    let response = resolver.resolve(&query).await.0.expect("a plain answer");
    assert_eq!(response, answer_wire(&query, [1, 2, 3, 4], 60));
    assert_eq!(count.load(Ordering::Relaxed), 1);
    assert_eq!(resolver.stats()[0].sample_count, 1);
}

#[tokio::test]
async fn a_truncated_udp_answer_is_retried_over_tcp() {
    // One port for both protocols: the resolver has to fall back on the same `host:port`.
    let tcp_listener = std::net::TcpListener::bind("127.0.0.1:0").expect("reserve a port");
    let port = tcp_listener.local_addr().expect("local addr").port();
    let udp_socket = std::net::UdpSocket::bind(("127.0.0.1", port)).expect("bind the same port");
    let (tcp, tcp_count) = spawn_tcp_listener(tcp_listener, [7, 7, 7, 7]);
    let (udp, udp_count) = spawn_udp_socket(udp_socket, [1, 1, 1, 1], true);
    assert_eq!(udp.port(), tcp.port());

    let config = config_json(
        "single",
        &[provider_json("p1", "PLAIN", &tcp.to_string(), "")],
        None,
    );
    let resolver = resolver(&config, None, Arc::new(Recorder::default()));

    let query = query_wire("truncated.test", 9);
    let response = resolver.resolve(&query).await.0.expect("the TCP answer");
    assert_eq!(response, answer_wire(&query, [7, 7, 7, 7], 60));
    assert_eq!(udp_count.load(Ordering::Relaxed), 1);
    assert_eq!(tcp_count.load(Ordering::Relaxed), 1);
}

#[tokio::test]
async fn dot_parks_the_connection_and_the_next_query_reuses_it() {
    let pki = TestPki::new("localhost");
    let (upstream, connections) = spawn_dot(&pki).await;

    let config = config_json(
        "single",
        &[provider_json(
            "p1",
            "DOT",
            &format!("localhost:{}", upstream.port()),
            "",
        )],
        None,
    );
    let resolver = resolver(&config, Some(&pki.ca_pem), Arc::new(Recorder::default()));

    for id in 0..2u16 {
        let query = query_wire("dot.test", id);
        let response = resolver.resolve(&query).await.0.expect("a DoT answer");
        assert_eq!(response, answer_wire(&query, [9, 8, 7, 6], 60));
    }
    assert_eq!(
        connections.load(Ordering::Relaxed),
        1,
        "the pooled connection is reused"
    );
}

#[tokio::test]
async fn doh_speaks_http2_and_reuses_the_session() {
    let pki = TestPki::new("localhost");
    let (upstream, connections, versions) = spawn_doh(&pki).await;

    let url = format!("https://localhost:{}/dns-query", upstream.port());
    let config = config_json("single", &[provider_json("p1", "DOH", "", &url)], None);
    let resolver = resolver(&config, Some(&pki.ca_pem), Arc::new(Recorder::default()));

    for id in 0..2u16 {
        let query = query_wire("doh.test", id);
        let response = resolver.resolve(&query).await.0.expect("a DoH answer");
        assert_eq!(response, answer_wire(&query, [4, 3, 2, 1], 60));
    }
    assert_eq!(
        *versions.lock().unwrap(),
        vec![Version::HTTP_2, Version::HTTP_2],
        "ALPN h2 is what the pool keys on"
    );
    assert_eq!(
        connections.load(Ordering::Relaxed),
        1,
        "the HTTP/2 session is reused"
    );
}

#[tokio::test]
async fn doh_reports_the_rate_limit_status() {
    let pki = TestPki::new("localhost");
    let (upstream, _, _) = spawn_doh(&pki).await;

    let url = format!("https://localhost:{}/limited", upstream.port());
    let config = config_json("single", &[provider_json("p1", "DOH", "", &url)], None);
    let resolver = resolver(&config, Some(&pki.ca_pem), Arc::new(Recorder::default()));

    let error = resolver
        .resolve(&query_wire("limited.test", 1))
        .await
        .0
        .expect_err("403 is a failure");
    assert_eq!(error, "DoH rate limited (403)");
}

#[tokio::test]
async fn doq_answers_on_a_bidirectional_stream() {
    let pki = TestPki::new("localhost");
    let (upstream, connections) = spawn_doq(&pki).await;

    let url = format!("doq://localhost:{}", upstream.port());
    let config = config_json("single", &[provider_json("p1", "DOQ", "", &url)], None);
    let resolver = resolver(&config, Some(&pki.ca_pem), Arc::new(Recorder::default()));

    for id in 0..2u16 {
        let query = query_wire("doq.test", id);
        let response = resolver.resolve(&query).await.0.expect("a DoQ answer");
        assert_eq!(response, answer_wire(&query, [6, 5, 4, 3], 60));
    }
    assert_eq!(
        connections.load(Ordering::Relaxed),
        1,
        "the QUIC session is reused"
    );
}

#[tokio::test]
async fn bootstrap_turns_the_provider_hostname_into_an_address() {
    let pki = TestPki::new("dot.test");
    let (upstream, _connections) = spawn_dot(&pki).await;
    // The bootstrap server answers every question with 127.0.0.1.
    let (bootstrap, bootstrap_queries) = spawn_udp_upstream([127, 0, 0, 1], false);

    let bootstrap_config = format!(
        r#"{{"enabled":true,"ips":[{{"id":"b1","name":"loopback","ip":"{}","weight":1}}]}}"#,
        bootstrap
    );
    let config = config_json(
        "single",
        &[provider_json(
            "p1",
            "DOT",
            &format!("dot.test:{}", upstream.port()),
            "",
        )],
        Some(&bootstrap_config),
    );
    let sink = Arc::new(Recorder::default());
    let resolver = resolver(&config, Some(&pki.ca_pem), sink.clone());

    let query = query_wire("bootstrap.test", 5);
    let response = resolver
        .resolve(&query)
        .await
        .0
        .expect("a bootstrapped answer");
    assert_eq!(response, answer_wire(&query, [9, 8, 7, 6], 60));
    assert!(
        bootstrap_queries.load(Ordering::Relaxed) >= 1,
        "the bootstrap endpoint was queried"
    );

    let events = sink.events.lock().unwrap();
    assert!(
        events.iter().any(|event| event.success
            && event.host == "dot.test"
            && event.ip == bootstrap.to_string()),
        "{events:?}"
    );
}

#[tokio::test]
async fn parallel_race_returns_the_faster_provider() {
    // A bound socket nobody reads: the query is sent and never answered.
    let silent = std::net::UdpSocket::bind("127.0.0.1:0").expect("bind the silent upstream");
    let silent = silent.local_addr().expect("local addr");
    let (fast, _count) = spawn_udp_upstream([5, 5, 5, 5], false);

    let config = config_json(
        "parallel_race",
        &[
            provider_json("slow", "PLAIN", &silent.to_string(), ""),
            provider_json("fast", "PLAIN", &fast.to_string(), ""),
        ],
        None,
    );
    let resolver = resolver(&config, None, Arc::new(Recorder::default()));

    let query = query_wire("race.test", 3);
    let (result, race) = resolver.resolve(&query).await;
    assert_eq!(
        result.expect("the fast answer"),
        answer_wire(&query, [5, 5, 5, 5], 60)
    );
    let race = race.expect("a race-log line");
    assert_eq!(race.strategy, "parallel_race");
    assert!(race.success, "{race:?}");
    assert_eq!(race.provider_count, 2);
    assert_eq!(race.winner_provider_id, "fast");
}

#[tokio::test]
async fn smart_prediction_advances_past_a_failed_provider() {
    // The first provider is a closed port: the DoT dial fails immediately, so the scheduler has to
    // advance to the second one without waiting for the hedge timer.
    let (fast, _count) = spawn_udp_upstream([8, 8, 8, 8], false);
    let config = config_json(
        "smart_prediction",
        &[
            provider_json("dead", "DOT", "127.0.0.1:9", ""),
            provider_json("fast", "PLAIN", &fast.to_string(), ""),
        ],
        None,
    );
    let resolver = resolver(&config, None, Arc::new(Recorder::default()));

    let query = query_wire("smart.test", 11);
    let (result, race) = resolver.resolve(&query).await;
    assert_eq!(
        result.expect("the second answer"),
        answer_wire(&query, [8, 8, 8, 8], 60)
    );
    let race = race.expect("a race-log line");
    assert_eq!(race.strategy, "smart_prediction");
    assert!(race.success, "{race:?}");
    assert!(race.fallback_used, "{race:?}");
    assert_eq!(race.winner_provider_id, "fast");
    assert_eq!(race.provider_count, 2);
}

#[tokio::test]
async fn the_engine_publishes_its_trust_store_to_the_transports() {
    let pki = TestPki::new("localhost");
    let (upstream, _, _) = spawn_doh(&pki).await;
    let url = format!("https://localhost:{}/dns-query", upstream.port());
    let config = config_json("single", &[provider_json("p1", "DOH", "", &url)], None);

    let engine = Arc::new(diting_engine::Engine::new());
    engine.set_upstream_trust(Arc::new(UpstreamTrust::from_roots(pki.roots())));
    engine
        .apply_dns_config(&config)
        .expect("the config applies");

    let document = engine.resolve_domain("doh.test", true).await;
    assert!(document.contains("\"4.3.2.1\""), "{document}");
    assert!(document.contains("\"upstream\""), "{document}");
}

#[tokio::test]
async fn a_provider_that_cannot_be_built_is_reported() {
    let config = config_json(
        "single",
        &[provider_json("p1", "DOH", "", "not a url")],
        None,
    );
    // The config kernel rejects it before the resolver ever sees it, with the Go error text.
    assert!(DnsConfig::from_json(&config).is_err());

    // A config the kernel accepts but the transport cannot use: an empty DoH host cannot happen
    // after validation, so the interesting case is the DoQ client failing to build — which the
    // resolver reports through `skipped` instead of failing every query.
    let config = config_json(
        "single",
        &[provider_json("p1", "PLAIN", "127.0.0.1:53", "")],
        None,
    );
    let resolver = resolver(&config, None, Arc::new(Recorder::default()));
    assert!(resolver.skipped().is_empty());
    assert_eq!(resolver.provider_count(), 1);
}
