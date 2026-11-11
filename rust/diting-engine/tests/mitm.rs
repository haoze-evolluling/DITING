//! MITM end to end: a real TLS client, the engine's handler, a real TLS origin.
//!
//! ```text
//! rustls client ──TCP──► bridge ──Inbound/Events──► mitm::handler::handle_tcp
//!                                                       │
//!                            diting-cert-core leaf ◄────┤ TLS accept
//!                                                       ├─► outbound dial (protected)
//!                                                       ├─► upstream TLS (platform pool)
//!                                                       └─► hyper HTTP/1.1 relay ↔ origin
//! ```
//!
//! Only the TUN device is substituted (the bridge plays the stack thread); the certificate chain,
//! the TLS handshakes, the HTTP exchange and the injected bytes are the production ones. The origin
//! is a loopback TLS server whose CA the engine is told to trust, and the client trusts the root that
//! `startStackMitm` wrote into a scratch `.go-mitm` directory.

mod support;

use std::sync::{Arc, Mutex};

use diting_engine::mitm::{HttpLogSink, MitmSettings};
use diting_engine::resolver::trust::{add_pem_roots, UpstreamTrust};
use diting_engine::tunnel::stats::TunnelCounters;
use diting_engine::Engine;
use rustls::RootCertStore;

use support::mitm::{
    spawn_flow, spawn_mtls_origin, spawn_origin, spawn_plain_origin, Client, HOST, PAGE,
};

const APP: &str = "com.test.app";
const UID: i32 = 10123;

/// The default cosmetic payload: any non-empty rule set turns injection on.
const COSMETIC_RULES: &str = r##"{"globalHide":["#ad"],"globalException":[],"domains":{}}"##;

/// A scratch `.go-mitm` directory per test, so the CA files never leak between cases.
fn scratch(label: &str) -> String {
    let dir = std::env::temp_dir().join(format!(
        "diting-engine-mitm-{label}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|elapsed| elapsed.as_micros())
            .unwrap_or(0)
    ));
    dir.to_string_lossy().into_owned()
}

/// An engine whose upstream trust is exactly the origin's CA, with MITM running on a scratch dir.
fn engine_with_mitm(label: &str, origin_ca: Option<&str>) -> (Arc<Engine>, String, String) {
    let engine = Arc::new(Engine::new());
    let roots = match origin_ca {
        Some(pem) => {
            let mut roots = RootCertStore::empty();
            assert_eq!(add_pem_roots(&mut roots, &[pem]), 1, "the origin CA loads");
            roots
        }
        None => RootCertStore::empty(),
    };
    engine.set_upstream_trust(Arc::new(UpstreamTrust::from_roots(roots)));
    let dir = scratch(label);
    let (pem, messages) = engine.mitm_state().start(&dir, &engine.upstream_trust());
    assert!(!pem.is_empty(), "MITM started: {messages:?}");
    (engine, pem, dir)
}

fn counters() -> Arc<TunnelCounters> {
    Arc::new(TunnelCounters::default())
}

/// A recording `HttpLogCallback`.
#[derive(Clone)]
struct HttpLog {
    rows: Arc<Mutex<Vec<Row>>>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct Row {
    package: String,
    authority: String,
    protocol: String,
    outcome: String,
    rule: String,
}

impl HttpLog {
    fn install(engine: &Arc<Engine>) -> HttpLog {
        let log = HttpLog {
            rows: Arc::new(Mutex::new(Vec::new())),
        };
        engine
            .mitm_state()
            .settings()
            .set_http_log(Some(Arc::new(log.clone())));
        log
    }

    fn rows(&self) -> Vec<Row> {
        self.rows.lock().expect("rows").clone()
    }

    fn outcomes(&self) -> Vec<String> {
        self.rows().into_iter().map(|row| row.outcome).collect()
    }
}

impl HttpLogSink for HttpLog {
    fn event(&self, package: &str, authority: &str, protocol: &str, outcome: &str, rule: &str) {
        self.rows.lock().expect("rows").push(Row {
            package: package.to_string(),
            authority: authority.to_string(),
            protocol: protocol.to_string(),
            outcome: outcome.to_string(),
            rule: rule.to_string(),
        });
    }
}

fn settings(engine: &Arc<Engine>) -> &MitmSettings {
    engine.mitm_state().settings()
}

fn link_tag(host: &str) -> String {
    format!(r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css?h={host}">"#)
}

fn page_with_link(host: &str) -> String {
    PAGE.replacen("<head>", &format!("<head>{}", link_tag(host)), 1)
}

// ---- the decryption path ------------------------------------------------------------------------

/// A TLS flow is terminated with a leaf for the SNI, relayed to the real origin, and the page comes
/// back with the stylesheet `<link>` spliced in.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_tls_flow_is_decrypted_and_the_stylesheet_link_is_injected() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("decrypt", Some(&origin.ca_pem));
    settings(&engine).set_cosmetic_rules(COSMETIC_RULES);
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_tls(bridge, HOST, &ca_pem)
        .await
        .expect("the client trusts the minted leaf");
    let (status, headers, body) = client
        .request(
            HOST,
            "/",
            &[("accept", "text/html,*/*"), ("accept-encoding", "gzip, br")],
        )
        .await;

    assert_eq!(status, 200);
    let text = String::from_utf8(body).expect("utf-8");
    assert_eq!(
        text,
        page_with_link(HOST),
        "the link is spliced into <head>"
    );
    assert!(
        headers.get("content-length").is_none() || headers.get("transfer-encoding").is_some(),
        "an injected body is re-framed: {headers:?}"
    );
    // `requestAcceptsHTML` → `Accept-Encoding` removed, so the upstream sent the page uncompressed.
    assert_eq!(
        origin.encoding_of(0),
        "",
        "the HTML request lost Accept-Encoding"
    );
    assert_eq!(origin.request_count(), 1);
    assert_eq!(origin.requests.lock().expect("requests")[0].0, HOST);

    // The client really did see our CA, not the origin's chain.
    let session = engine.mitm_state().session().expect("the session is live");
    assert_eq!(client.peer_certificates.len(), 2, "leaf then root");
    assert_eq!(
        client.peer_certificates[1].as_ref(),
        session.certs().authority().ca_der(),
        "the root the client trusts is the engine's CA"
    );

    engine.mitm_state().stop();
    assert!(!engine.mitm_state().active());
    let _ = std::fs::remove_dir_all(dir);
}

/// A gzip HTML page is decoded, injected and re-framed as chunked, and the origin's own bytes stay
/// on the wire until the relay decodes them.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_gzipped_page_is_injected_and_the_connection_stays_usable() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("gzip", Some(&origin.ca_pem));
    settings(&engine).set_cosmetic_rules(COSMETIC_RULES);
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_tls(bridge, HOST, &ca_pem)
        .await
        .expect("handshake");
    // No `Accept: text/html`, so the client keeps its `Accept-Encoding` and the origin gzips.
    let (status, headers, body) = client.request(HOST, "/gzip", &[]).await;
    assert_eq!(status, 200);
    assert_eq!(headers.get("content-encoding"), None, "the body is decoded");
    assert_eq!(
        String::from_utf8(body).expect("utf-8"),
        page_with_link(HOST)
    );

    // keep-alive survives injection: a second request on the same connection is relayed.
    let (status, _, body) = client.request(HOST, "/plain", &[]).await;
    assert_eq!(status, 200);
    assert_eq!(body, b"not a page");
    assert_eq!(origin.request_count(), 2);

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// Plaintext HTTP on `:80` takes the same relay without TLS termination.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_plaintext_http_flow_is_relayed_and_injected() {
    let origin = spawn_plain_origin().await;
    let (engine, _, dir) = engine_with_mitm("http", None);
    settings(&engine).set_cosmetic_rules(COSMETIC_RULES);
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_plain(bridge).await;
    let (status, _, body) = client.request(HOST, "/", &[("accept", "text/html")]).await;
    assert_eq!(status, 200);
    assert_eq!(
        String::from_utf8(body).expect("utf-8"),
        page_with_link(HOST)
    );
    assert_eq!(origin.request_count(), 1);

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

// ---- the local-only paths -----------------------------------------------------------------------

/// The stylesheet origin is answered by the engine: no upstream connection is ever dialed.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn the_local_asset_stylesheet_is_served_without_dialing_the_origin() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("assets", Some(&origin.ca_pem));
    settings(&engine).set_cosmetic_rules(
        r##"{"globalHide":["#ad"],"globalException":[],
            "domains":{"upstream.test":{"hide":[".banner"],"exception":[]}}}"##,
    );
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_tls(bridge, "local.pwhs.app", &ca_pem)
        .await
        .expect("the asset host's leaf is minted for it");
    let (status, headers, body) = client
        .request("local.pwhs.app", "/cosmetic.css?h=upstream.test", &[])
        .await;
    assert_eq!(status, 200);
    assert_eq!(
        headers
            .get("content-type")
            .and_then(|value| value.to_str().ok()),
        Some("text/css; charset=utf-8")
    );
    let css = String::from_utf8(body).expect("utf-8");
    assert!(css.contains("#ad { display: none !important; }"), "{css}");
    assert!(
        css.contains(".banner { display: none !important; }"),
        "{css}"
    );
    assert_eq!(
        origin.request_count(),
        0,
        "the asset never leaves the device"
    );

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// A CNAME rewrite becomes a 302 to the target, request URI preserved.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_rewritten_host_answers_with_a_302_to_the_target() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("rewrite", Some(&origin.ca_pem));
    engine.set_rewrite_rules(r#"{"rewritten.test":"target.test"}"#);
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_tls(bridge, "rewritten.test", &ca_pem)
        .await
        .expect("handshake");
    let (status, headers, body) = client.request("rewritten.test", "/path?q=1", &[]).await;
    assert_eq!(status, 302);
    assert_eq!(
        headers
            .get("location")
            .and_then(|value| value.to_str().ok()),
        Some("https://target.test/path?q=1")
    );
    assert!(body.is_empty());
    assert_eq!(origin.request_count(), 0);

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

// ---- the passthrough and refusal paths ----------------------------------------------------------

/// A bypassed host is relayed as opaque bytes: the client sees the origin's own certificate.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_bypassed_host_is_not_decrypted() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("bypass", Some(&origin.ca_pem));
    settings(&engine).set_cosmetic_rules(COSMETIC_RULES);
    let session = engine.mitm_state().session().expect("the session is live");
    // The bypass rule names the origin's own host, so the client can verify the real chain.
    assert_eq!(session.filter().set_bypass_rules(HOST), 1);
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    // The origin's CA, not the engine's: the client is talking to the real server.
    let mut client = Client::connect_tls(bridge, HOST, &origin.ca_pem)
        .await
        .expect("the passthrough relay keeps the handshake alive");
    let (status, _, body) = client.request(HOST, "/", &[]).await;
    assert_eq!(status, 200);
    assert_eq!(body, PAGE.as_bytes(), "the page is not injected");
    assert_ne!(
        client.peer_certificates[1].as_ref(),
        session.certs().authority().ca_der(),
        "the client saw the origin's chain, not ours"
    );
    let _ = ca_pem;

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// A domain rule blocks the host before the handshake, and the HTTP log records why.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_blocked_host_is_dropped_before_the_handshake() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("blocked", Some(&origin.ca_pem));
    let log = HttpLog::install(&engine);
    assert_eq!(
        engine.apply_rule_snapshot(
            r#"{"filterEnabled":true,"globalBlock":["blocked.test"],
                "globalAllow":[],"globalImportant":[]}"#
        ),
        ""
    );
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let attempt = Client::connect_tls(bridge, "blocked.test", &ca_pem).await;
    assert!(attempt.is_err(), "the flow is dropped, not decrypted");
    assert_eq!(log.outcomes(), vec!["blocked".to_string()]);
    assert!(
        log.rows()[0].rule.contains("blocked.test"),
        "the matched rule is reported: {:?}",
        log.rows()[0]
    );
    assert_eq!(origin.request_count(), 0);

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// An upstream `CertificateRequest` is refused, logged and blacklisted for a week.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn an_mtls_upstream_is_blacklisted_and_never_relayed() {
    let origin = spawn_mtls_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("mtls", Some(&origin.ca_pem));
    let log = HttpLog::install(&engine);
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_tls(bridge, HOST, &ca_pem)
        .await
        .expect("the client handshake still happens first");
    assert!(
        client.try_request(HOST, "/", &[]).await.is_err(),
        "a refused upstream sends no page"
    );

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while std::time::Instant::now() < deadline && log.outcomes().is_empty() {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert_eq!(log.outcomes(), vec!["handshake_failed".to_string()]);
    assert_eq!(log.rows()[0].rule, "client-certificate (mTLS) request");
    let session = engine.mitm_state().session().expect("the session is live");
    assert_eq!(
        session
            .filter()
            .blacklist_count(diting_engine::mitm::now_ms()),
        1
    );
    let file = std::fs::read_to_string(session.blacklist_path()).expect("the blacklist file");
    assert!(file.contains(HOST), "{file}");

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// A client that refuses the minted leaf costs one failure streak and no upstream traffic.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_client_that_rejects_the_leaf_records_a_handshake_failure() {
    let origin = spawn_origin().await;
    let (engine, _, dir) = engine_with_mitm("client_tls", Some(&origin.ca_pem));
    let log = HttpLog::install(&engine);
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    // A different CA: the client has no reason to trust the engine's leaf.
    let other = spawn_origin().await;
    let refused = Client::connect_tls(bridge, HOST, &other.ca_pem).await;
    assert!(refused.is_err(), "the client rejects the minted leaf");
    assert_eq!(origin.request_count(), 0, "no upstream connection was made");

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while std::time::Instant::now() < deadline && log.outcomes().is_empty() {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    assert_eq!(log.outcomes(), vec!["handshake_failed".to_string()]);
    assert_eq!(log.rows()[0].rule, "client_tls");

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

// ---- the relay's own decisions ------------------------------------------------------------------

/// The request rules answer with the Go 403 and the matched pattern in the log.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_request_rule_answers_403_with_the_matched_pattern() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("request_rule", Some(&origin.ca_pem));
    let log = HttpLog::install(&engine);
    settings(&engine)
        .set_request_rules(r#"[{"pattern":"https://upstream.test/ads","kind":"block"}]"#)
        .expect("the rules parse");
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_tls(bridge, HOST, &ca_pem)
        .await
        .expect("handshake");
    let (status, _, body) = client.request(HOST, "/ads/banner.js", &[]).await;
    assert_eq!(status, 403);
    assert_eq!(body, b"Blocked by DITING");
    assert_eq!(log.outcomes(), vec!["blocked".to_string()]);
    assert_eq!(log.rows()[0].rule, "https://upstream.test/ads");
    assert_eq!(origin.request_count(), 0);

    // An allowed path still goes through.
    let (status, _, _) = client.request(HOST, "/", &[]).await;
    assert_eq!(status, 200);
    assert_eq!(origin.request_count(), 1);

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// The `HTTP` log row carries the package the gate resolved and the protocol column the UI reads.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn the_http_log_rows_carry_the_package_and_protocol() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("http_log", Some(&origin.ca_pem));
    let log = HttpLog::install(&engine);
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_tls(bridge, HOST, &ca_pem)
        .await
        .expect("handshake");
    let (status, _, _) = client.request(HOST, "/", &[]).await;
    assert_eq!(status, 200);

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    while std::time::Instant::now() < deadline && log.outcomes().is_empty() {
        std::thread::sleep(std::time::Duration::from_millis(20));
    }
    let rows = log.rows();
    assert_eq!(rows.len(), 1, "{rows:?}");
    assert_eq!(rows[0].package, APP);
    assert_eq!(rows[0].authority, HOST);
    assert_eq!(rows[0].protocol, "HTTPS");
    assert_eq!(rows[0].outcome, "allowed");

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// The relay counts the bytes it wrote to the client as `rx`, and the session counts `tx`.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn the_relay_counts_the_response_bytes_as_rx() {
    let origin = spawn_origin().await;
    let (engine, ca_pem, dir) = engine_with_mitm("traffic", Some(&origin.ca_pem));
    let bridge = spawn_flow(Arc::clone(&engine), counters(), origin.address, UID, APP).await;

    let mut client = Client::connect_tls(bridge, HOST, &ca_pem)
        .await
        .expect("handshake");
    let (status, _, _) = client.request(HOST, "/plain", &[]).await;
    assert_eq!(status, 200);

    let deadline = std::time::Instant::now() + std::time::Duration::from_secs(5);
    let mut seen = 0u64;
    while std::time::Instant::now() < deadline && seen == 0 {
        std::thread::sleep(std::time::Duration::from_millis(20));
        seen = engine
            .traffic()
            .tick()
            .iter()
            .filter(|delta| delta.uid == UID)
            .map(|delta| delta.rx)
            .sum();
    }
    assert!(seen > 0, "the response bytes are counted for UID {UID}");

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// `startStackMitm` twice reuses the CA on disk, so an installed root keeps validating.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn the_ca_on_disk_survives_a_stop_and_start() {
    let origin = spawn_origin().await;
    let (engine, first_pem, dir) = engine_with_mitm("restart", Some(&origin.ca_pem));
    engine.mitm_state().stop();
    let (second_pem, messages) = engine.mitm_state().start(&dir, &engine.upstream_trust());
    assert_eq!(
        first_pem, second_pem,
        "the root is reloaded, not regenerated"
    );
    assert!(messages
        .iter()
        .any(|line| line.contains("loaded from disk")));
    assert!(std::path::Path::new(&dir).join("ca.crt").is_file());
    assert!(std::path::Path::new(&dir).join("ca.key").is_file());

    // A fresh engine that never started MITM still reads the root back for the settings screen.
    assert_eq!(diting_engine::mitm::ca_pem_from(&dir), first_pem);
    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}

/// The gate selects `Intercept` only for a selected UID on `:80`/`:443`.
#[test]
fn the_mitm_gate_only_intercepts_the_selected_apps_http_ports() {
    use diting_engine::netstack::TcpKey;
    use diting_engine::tunnel::gate::{admit_mitm_flow, FlowAction, FlowContext};
    use support::wire::endpoint_v4;

    let dir = scratch("gate");
    let engine = Arc::new(Engine::new());
    let (pem, messages) = engine.mitm_state().start(&dir, &engine.upstream_trust());
    assert!(!pem.is_empty(), "MITM started: {messages:?}");
    let session = engine.mitm_state().session().expect("the session is live");
    assert_eq!(session.filter().set_allowed_uids_csv(&UID.to_string()), 1);

    let context = FlowContext {
        uid: UID,
        app: APP.to_string(),
    };
    let app = endpoint_v4([10, 0, 0, 2], 40000);
    let https = TcpKey::new(endpoint_v4([93, 184, 216, 34], 443), app);
    let http = TcpKey::new(endpoint_v4([93, 184, 216, 34], 80), app);
    let mysql = TcpKey::new(endpoint_v4([93, 184, 216, 34], 3306), app);
    assert_eq!(
        admit_mitm_flow(&engine, &https, &context),
        FlowAction::Intercept
    );
    assert_eq!(
        admit_mitm_flow(&engine, &http, &context),
        FlowAction::Intercept
    );
    assert_eq!(
        admit_mitm_flow(&engine, &mysql, &context),
        FlowAction::Relay,
        "only :80 and :443 are intercepted"
    );
    let other = FlowContext {
        uid: UID + 1,
        app: "com.other.app".to_string(),
    };
    assert_eq!(
        admit_mitm_flow(&engine, &https, &other),
        FlowAction::Relay,
        "an app outside the allow list is relayed"
    );
    // A private destination is relayed even for a selected app, like Go's `isLoopbackOrInternal`.
    let private = TcpKey::new(endpoint_v4([192, 168, 1, 1], 443), app);
    assert_eq!(
        admit_mitm_flow(&engine, &private, &context),
        FlowAction::Relay
    );

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}
