//! End-to-end proof that the Rust MITM relay preserves the semantics the Go engine depended on.
//!
//! Each test runs a real TLS origin, the proxy and a real TLS client on loopback. The assertions are
//! the semantics the migration had to preserve: what the client sees on the wire (leaf, ALPN, headers,
//! body framing) and what the origin sees on the request.

mod support;

use std::sync::Arc;

use async_compression::tokio::bufread::{DeflateEncoder, GzipEncoder, ZlibEncoder};
use bytes::Bytes;
use der::Decode;
use diting_cert_core::ca::{subject, CA_COMMON_NAME};
use diting_mitm_spike::relay::{
    HttpEvent, Proxy, PROTOCOL_HTTPS, STATUS_ALLOWED, STATUS_HANDSHAKE_FAILED,
    STATUS_UPSTREAM_FAILED,
};
use http::{header, StatusCode};
use support::*;
use tokio::io::AsyncReadExt;
use x509_cert::Certificate;

const HTML_PAGE: &str = "<html><head><title>page</title></head><body>hi</body></html>";
const LINK_PREFIX: &str =
    r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css?h=upstream.test">"#;

#[tokio::test]
async fn the_handshake_uses_a_leaf_minted_for_the_sni() {
    let pki = Pki::new();
    let origin = spawn_origin(&pki, OriginAuth::Plain, |_request, _record| text("ok")).await;
    let proxy = spawn_proxy(&pki, &origin, false, true).await;

    // A browser offers h2 first; the relay only speaks HTTP/1.1, so ALPN must land on http/1.1.
    let mut client = TestClient::connect(
        proxy.addr,
        UPSTREAM_HOST,
        pki.mitm_ca_pem(),
        &[b"h2", b"http/1.1"],
    )
    .await
    .expect("the handshake succeeds");
    assert_eq!(client.alpn(), Some(&b"http/1.1"[..]));

    let certificates = client.peer_certificates();
    assert_eq!(
        certificates.len(),
        2,
        "leaf plus root, like tls.X509KeyPair"
    );
    let leaf = Certificate::from_der(certificates[0].as_ref()).expect("parse the leaf");
    let root = Certificate::from_der(certificates[1].as_ref()).expect("parse the root");
    let (leaf_cn, leaf_org) = subject(&leaf);
    assert_eq!(leaf_cn.as_deref(), Some(UPSTREAM_HOST));
    assert_eq!(leaf_org, vec!["DITING".to_string()]);
    assert_eq!(subject(&root).0.as_deref(), Some(CA_COMMON_NAME));

    let response = client.get("/").await.expect("GET /");
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(collect_text(response).await, "ok");
}

#[tokio::test]
async fn a_client_that_offers_only_h2_cannot_be_intercepted() {
    let pki = Pki::new();
    let origin = spawn_origin(&pki, OriginAuth::Plain, |_request, _record| text("ok")).await;
    let proxy = spawn_proxy(&pki, &origin, false, true).await;

    let failure = TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"h2"]).await;
    assert!(
        failure.is_err(),
        "no overlapping ALPN must abort the handshake"
    );

    let event = event_with_status(&proxy.proxy, STATUS_HANDSHAKE_FAILED).await;
    assert!(
        event.reason.starts_with("client_tls"),
        "got {:?}",
        event.reason
    );
}

#[tokio::test]
async fn an_injected_html_page_is_chunked_and_the_connection_stays_usable() {
    let pki = Pki::new();
    let origin = spawn_origin(&pki, OriginAuth::Plain, |_request, _record| {
        let mut response = html(HTML_PAGE);
        response.headers_mut().insert(
            "content-security-policy",
            "default-src 'none'".parse().expect("valid header"),
        );
        response
    })
    .await;
    let proxy = spawn_proxy(&pki, &origin, true, true).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("handshake");

    let response = client
        .get_accepting("/", "text/html,*/*")
        .await
        .expect("GET /");
    assert_eq!(response.status(), StatusCode::OK);
    assert!(
        response.headers().get(header::CONTENT_LENGTH).is_none(),
        "an injected body has no known length"
    );
    assert!(response.headers().get(header::CONTENT_ENCODING).is_none());
    assert!(
        response.headers().get("content-security-policy").is_none(),
        "the upstream CSP no longer describes the page"
    );
    let body = collect_text(response).await;
    assert!(
        body.contains(LINK_PREFIX),
        "the tag is spliced after <head>: {body}"
    );
    assert!(body.starts_with("<html><head><link"));

    // The chunked framing terminates properly, so keep-alive survives an injected response. Go had to
    // force `Connection: close` because net/http refused to chunk it.
    let second = client.get("/again").await.expect("second request");
    assert_eq!(second.status(), StatusCode::OK);
    let second_body = collect_text(second).await;
    assert!(
        second_body.contains(LINK_PREFIX),
        "the second page on the same connection is injected too: {second_body}"
    );

    let event = event_with_status(&proxy.proxy, STATUS_ALLOWED).await;
    assert_eq!(event.host, UPSTREAM_HOST);
    assert_eq!(event.protocol, PROTOCOL_HTTPS);
}

#[tokio::test]
async fn accept_encoding_is_stripped_only_for_html_clients() {
    let pki = Pki::new();
    let origin = spawn_origin(&pki, OriginAuth::Plain, |_request, record| {
        text(record.header("accept-encoding").unwrap_or("<none>"))
    })
    .await;
    let proxy = spawn_proxy(&pki, &origin, false, true).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("handshake");

    let html_request = client
        .get_accepting("/page", "text/html,*/*")
        .await
        .expect("GET");
    assert_eq!(collect_text(html_request).await, "<none>");

    let json_request = client
        .get_accepting("/api", "application/json")
        .await
        .expect("GET");
    assert_eq!(collect_text(json_request).await, "gzip, deflate");

    let seen = origin.seen();
    assert_eq!(seen.len(), 2, "both requests reached the origin");
}

#[tokio::test]
async fn a_gzip_html_body_is_decoded_and_injected() {
    let pki = Pki::new();
    let compressed = Arc::new(gzip(HTML_PAGE.as_bytes()).await);
    let origin = spawn_origin(&pki, OriginAuth::Plain, move |_request, _record| {
        let mut response = respond(
            StatusCode::OK,
            "text/html; charset=utf-8",
            Bytes::from(compressed.as_ref().clone()),
        );
        response.headers_mut().insert(
            header::CONTENT_ENCODING,
            "gzip".parse().expect("valid header"),
        );
        response
    })
    .await;
    let proxy = spawn_proxy(&pki, &origin, true, true).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("handshake");

    // No Accept header at all: the proxy must still decode, because the upstream ignored the fact
    // that its Accept-Encoding was removed.
    let response = client.get("/").await.expect("GET /");
    assert!(response.headers().get(header::CONTENT_ENCODING).is_none());
    let body = collect_text(response).await;
    assert!(body.starts_with("<html><head><link"), "{body}");
    assert!(body.ends_with("</body></html>"));
}

#[tokio::test]
async fn both_deflate_spellings_are_decoded() {
    let pki = Pki::new();
    let zlib_body = Arc::new(zlib(HTML_PAGE.as_bytes()).await);
    let raw_body = Arc::new(deflate(HTML_PAGE.as_bytes()).await);
    let origin = spawn_origin(&pki, OriginAuth::Plain, move |request, _record| {
        let (payload, _) = if request.uri().path() == "/zlib" {
            (zlib_body.clone(), ())
        } else {
            (raw_body.clone(), ())
        };
        let mut response = respond(
            StatusCode::OK,
            "text/html; charset=utf-8",
            Bytes::from(payload.as_ref().clone()),
        );
        response.headers_mut().insert(
            header::CONTENT_ENCODING,
            "deflate".parse().expect("valid header"),
        );
        response
    })
    .await;
    let proxy = spawn_proxy(&pki, &origin, true, true).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("handshake");

    for path in ["/zlib", "/raw"] {
        let response = client.get(path).await.expect("GET");
        let body = collect_text(response).await;
        assert!(
            body.starts_with("<html><head><link"),
            "{path} was not decoded and injected: {body}"
        );
    }
}

#[tokio::test]
async fn a_binary_body_is_forwarded_byte_for_byte() {
    let pki = Pki::new();
    let payload: Vec<u8> = (0..=255u8).cycle().take(64 * 1024).collect();
    let expected = payload.clone();
    let origin = spawn_origin(&pki, OriginAuth::Plain, move |_request, _record| {
        respond(
            StatusCode::OK,
            "application/octet-stream",
            Bytes::from(payload.clone()),
        )
    })
    .await;
    let proxy = spawn_proxy(&pki, &origin, true, true).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("handshake");

    let response = client.get("/blob").await.expect("GET");
    assert_eq!(collect(response).await, expected);
}

#[tokio::test]
async fn a_chunked_upstream_body_streams_through() {
    let pki = Pki::new();
    let origin = spawn_origin(&pki, OriginAuth::Plain, |_request, _record| {
        streamed(
            "text/plain; charset=utf-8",
            vec![
                Bytes::from_static(b"chunk-one;"),
                Bytes::from_static(b"chunk-two;"),
                Bytes::from_static(b"chunk-three"),
            ],
        )
    })
    .await;
    let proxy = spawn_proxy(&pki, &origin, true, true).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("handshake");

    let response = client.get("/stream").await.expect("GET");
    assert_eq!(
        collect_text(response).await,
        "chunk-one;chunk-two;chunk-three"
    );
}

#[tokio::test]
async fn an_untrusted_upstream_certificate_is_fail_closed() {
    let pki = Pki::new();
    let origin = spawn_origin(&pki, OriginAuth::Plain, |_request, _record| text("secret")).await;
    // The proxy's trust store is empty: the origin's CA is not in it.
    let proxy = spawn_proxy(&pki, &origin, true, false).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("the client still trusts the proxy");

    let response = client.get("/").await.expect("GET /");
    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
    let event = event_with_status(&proxy.proxy, STATUS_UPSTREAM_FAILED).await;
    assert_eq!(event.host, UPSTREAM_HOST);
}

#[tokio::test]
async fn an_mtls_client_certificate_request_blocks_interception() {
    let pki = Pki::new();
    let origin = spawn_origin(&pki, OriginAuth::RequestClientCert, |_request, _record| {
        text("never relayed")
    })
    .await;
    let proxy = spawn_proxy(&pki, &origin, true, true).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("the client still trusts the proxy");

    let response = client.get("/").await.expect("GET /");
    assert_eq!(response.status(), StatusCode::BAD_GATEWAY);
    let event = event_with_status(&proxy.proxy, STATUS_HANDSHAKE_FAILED).await;
    assert!(
        event.reason.contains("client-certificate"),
        "got {:?}",
        event.reason
    );
}

#[tokio::test]
async fn a_dead_upstream_connection_is_replaced_before_the_next_request() {
    let pki = Pki::new();
    // Every connection this origin serves is closed right after the response, with no
    // `Connection: close` header, which is how a real server loses keep-alive silently.
    let origin = spawn_raw_origin(&pki).await;
    let proxy = spawn_proxy_at(&pki, origin.addr, false, true).await;
    let mut client =
        TestClient::connect(proxy.addr, UPSTREAM_HOST, pki.mitm_ca_pem(), &[b"http/1.1"])
            .await
            .expect("handshake");

    for path in ["/one", "/two"] {
        let response = client.get(path).await.expect("GET");
        assert_eq!(response.status(), StatusCode::OK, "{path}");
        assert_eq!(collect_text(response).await, "ok", "{path}");
    }
    assert_eq!(
        origin.connections.load(std::sync::atomic::Ordering::SeqCst),
        2,
        "the proxy reconnects upstream instead of failing the second request"
    );
}

/// Waits for the first event with `status`; the relay records from spawned tasks, so this polls.
async fn event_with_status(proxy: &Proxy, status: &str) -> HttpEvent {
    for _ in 0..300 {
        if let Some(event) = proxy
            .events()
            .into_iter()
            .find(|event| event.status == status)
        {
            return event;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    panic!("no {status} event: {:?}", proxy.events());
}

async fn gzip(input: &[u8]) -> Vec<u8> {
    let mut encoder = GzipEncoder::new(input);
    let mut output = Vec::new();
    encoder.read_to_end(&mut output).await.expect("gzip");
    output
}

async fn zlib(input: &[u8]) -> Vec<u8> {
    let mut encoder = ZlibEncoder::new(input);
    let mut output = Vec::new();
    encoder.read_to_end(&mut output).await.expect("zlib");
    output
}

async fn deflate(input: &[u8]) -> Vec<u8> {
    let mut encoder = DeflateEncoder::new(input);
    let mut output = Vec::new();
    encoder.read_to_end(&mut output).await.expect("deflate");
    output
}
