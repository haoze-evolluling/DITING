//! N7: a real DoH-over-HTTP/3 exchange against a loopback QUIC origin. Proves the request framing,
//! the SETTINGS/QPACK stream setup and the DATA extraction work end to end, not just in unit tests.

mod support;

use std::sync::Arc;

use diting_engine::protect::ProtectorHandle;
use diting_engine::resolver::doh3::Doh3Client;
use diting_engine::resolver::dial::Dialer;
use diting_engine::resolver::trust::UpstreamTrust;
use diting_engine::resolver::Bootstrap;

use support::{
    answer_wire, config_json, provider_json, query_wire, resolver, spawn_doh, spawn_doh3,
    spawn_doh3_on, Recorder, TestPki,
};

#[tokio::test]
async fn an_advertised_origin_upgrades_to_doh3_and_keeps_the_answer() {
    let pki = TestPki::new("localhost");
    let (upstream, _, _) = spawn_doh(&pki).await;
    // A real DoH3 origin listening on the same port the Alt-Svc advertisement names.
    let (_, h3_connections) = spawn_doh3_on(&pki, upstream).await;

    let url = format!("https://localhost:{}/dns-query", upstream.port());
    let config = config_json("single", &[provider_json("p1", "DOH", "", &url)], None);
    let resolver = resolver(&config, Some(&pki.ca_pem), Arc::new(Recorder::default()));
    assert!(!resolver.doh3_ready(), "nothing advertised before the first answer");

    let first = query_wire("first.test", 1);
    assert_eq!(
        resolver.resolve(&first).await.0.expect("a DoH answer"),
        answer_wire(&first, [4, 3, 2, 1], 60)
    );
    assert!(resolver.doh3_ready(), "the DoH answer advertised h3");

    let second = query_wire("second.test", 2);
    assert_eq!(
        resolver.resolve(&second).await.0.expect("a DoH3 answer"),
        answer_wire(&second, [4, 3, 2, 1], 60)
    );
    assert_eq!(
        h3_connections.load(std::sync::atomic::Ordering::Relaxed),
        1,
        "the second query was served over HTTP/3"
    );
}

#[tokio::test]
async fn doh3_answers_and_reuses_the_quic_connection() {
    let pki = TestPki::new("localhost");
    let (upstream, connections) = spawn_doh3(&pki).await;

    let trust = UpstreamTrust::from_roots(pki.roots());
    let client = Doh3Client::new(&trust).expect("the DoH3 client builds");
    let dialer = Dialer::new(
        Arc::new(Bootstrap::new(Arc::new(Recorder::default()))),
        ProtectorHandle::new(),
    );

    for id in [1u16, 2] {
        let query = query_wire("doh3.test", id);
        let answer = client
            .query(
                &dialer,
                "localhost",
                upstream.port(),
                "/dns-query",
                &query,
            )
            .await
            .expect("a DoH3 answer");
        // The same answer the DoH/DoQ origins give: DoH3 must not change the resolution result.
        assert_eq!(answer, answer_wire(&query, [4, 3, 2, 1], 60));
    }
    // N7 connection reuse: both queries ride one QUIC connection.
    assert_eq!(
        connections.load(std::sync::atomic::Ordering::Relaxed),
        1,
        "the QUIC connection is reused across queries"
    );
}
