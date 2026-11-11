//! The MITM corpus: the HTTP response bodies that get the cosmetic `<link>` spliced in.
//!
//! `android/engine/mitm_common.go` decided two things per exchange — whether the request loses
//! `Accept-Encoding` (`requestAcceptsHTML`) and whether the response body is rewritten
//! (`ShouldInjectHTML`) — and then streamed the body through the kernel's scanner. All three now live
//! in Rust (`diting-mitm-spike::inject` + `diting-cosmetic-core`), so the corpus freezes:
//!
//! * the decision for a set of request/response header combinations;
//! * the exact bytes that reach the client for the same page encoded four ways (identity, gzip, zlib,
//!   raw deflate) and for a page whose `<head>` is spelled in upper case.
//!
//! The bodies are deliberately smaller than the adapter's 16 KiB read buffer: a larger page's
//! output depends on how the upstream happened to be chunked, and that behaviour is covered by
//! `diting-mitm-spike`'s own unit tests rather than by a byte fixture.
//!
//! A full TLS transcript is *not* here (it needs a peer and a clock).

use async_compression::tokio::bufread::{DeflateEncoder, GzipEncoder, ZlibEncoder};
use diting_cosmetic_core::local::ASSET_HOST;
use diting_cosmetic_core::{link_tag, Injector};
use diting_mitm_spike::inject::{is_html, is_zlib_stream, request_accepts_html, InjectingReader};
use tokio::io::{AsyncBufReadExt, AsyncReadExt};

use crate::{hex, unhex};

/// One corpus case.
pub struct Case {
    pub id: &'static str,
    pub host: &'static str,
    pub content_type: &'static str,
    /// `Content-Encoding` as the upstream sent it.
    pub encoding: &'static str,
    /// The client's `Accept` header.
    pub accept: &'static str,
    /// The decompressed page.
    pub page: &'static [u8],
}

const PAGE: &[u8] = b"<html><head><title>corpus</title></head><body>hi</body></html>";
const UPPER_PAGE: &[u8] = b"<HTML><HEAD><title>corpus</title></HEAD><BODY>hi</BODY></HTML>";

pub fn cases() -> Vec<Case> {
    vec![
        Case {
            id: "plain-html",
            host: "example.test",
            content_type: "text/html; charset=utf-8",
            encoding: "",
            accept: "text/html,*/*",
            page: PAGE,
        },
        Case {
            id: "gzip-html",
            host: "example.test",
            content_type: "text/html; charset=utf-8",
            encoding: "gzip",
            accept: "text/html,*/*",
            page: PAGE,
        },
        Case {
            id: "zlib-html",
            host: "news.example.test",
            content_type: "text/html",
            encoding: "deflate",
            accept: "text/html",
            page: PAGE,
        },
        Case {
            id: "raw-deflate-html",
            host: "news.example.test",
            content_type: "text/html",
            encoding: "deflate",
            accept: "text/html",
            page: PAGE,
        },
        Case {
            id: "uppercase-head-html",
            host: "shop.example.test",
            content_type: "TEXT/HTML; charset=UTF-8",
            encoding: "",
            accept: "application/xhtml+xml,text/html",
            page: UPPER_PAGE,
        },
        Case {
            id: "non-html-passthrough",
            host: "api.example.test",
            content_type: "application/json",
            encoding: "",
            accept: "application/json",
            page: b"{\"ok\":true}",
        },
    ]
}

/// Builds the fixture document.
pub fn build() -> String {
    let cases: Vec<serde_json::Value> = cases()
        .into_iter()
        .map(|case| {
            // The raw-deflate case is the same `Content-Encoding: deflate` header with a body that
            // has no zlib header, which is what the relay's sniff has to tell apart.
            let encoded = if case.id == "raw-deflate-html" {
                encode_raw_deflate(case.page)
            } else {
                encode(case.encoding, case.page)
            };
            let (body, injected) = match encoded {
                Ok(body) => {
                    let injected = inject(&case, &body).expect("the injection path runs");
                    (body, injected)
                }
                Err(err) => panic!("{}: {err}", case.id),
            };
            serde_json::json!({
                "id": case.id,
                "host": case.host,
                "contentType": case.content_type,
                "contentEncoding": case.encoding,
                "accept": case.accept,
                "decisions": {
                    "acceptsHtml": request_accepts_html(case.accept),
                    "contentIsHtml": is_html(case.content_type),
                },
                "link": link_for(case.host),
                "body": hex(&body),
                "injected": injected.map(|bytes| hex(&bytes)),
            })
        })
        .collect();

    serde_json::json!({
        "note": "Stage 0 MITM corpus: the header decisions and the exact bytes of an injected HTML \
                 page, per content encoding. Generated by `cargo run -p diting-corpus --bin \
                 gen-corpus`; the producers are diting-mitm-spike::inject and diting-cosmetic-core.",
        "cases": cases,
    })
    .to_string()
}

fn link_for(host: &str) -> String {
    link_tag(host, ASSET_HOST)
}

/// Compresses `page` the way an upstream would for the given `Content-Encoding`.
fn encode(encoding: &str, page: &[u8]) -> Result<Vec<u8>, String> {
    let runtime = runtime();
    runtime.block_on(async move {
        match encoding {
            "" | "identity" => Ok(page.to_vec()),
            "gzip" => read_all(GzipEncoder::new(page)).await,
            "deflate" => read_all(ZlibEncoder::new(page)).await,
            other => Err(format!("unknown encoding {other}")),
        }
    })
}

/// Raw deflate, for the `deflate`-without-zlib-header case.
fn encode_raw_deflate(page: &[u8]) -> Result<Vec<u8>, String> {
    runtime().block_on(async move { read_all(DeflateEncoder::new(page)).await })
}

async fn read_all<R: tokio::io::AsyncRead + Unpin>(mut reader: R) -> Result<Vec<u8>, String> {
    let mut out = Vec::new();
    reader
        .read_to_end(&mut out)
        .await
        .map_err(|err| format!("read: {err}"))?;
    Ok(out)
}

/// Runs the production injection path over `body`; `None` when the response is not an HTML page.
fn inject(case: &Case, body: &[u8]) -> Result<Option<Vec<u8>>, String> {
    if !is_html(case.content_type) {
        return Ok(None);
    }
    let link = link_for(case.host);
    runtime().block_on(async move {
        let reader: Box<dyn tokio::io::AsyncRead + Send + Unpin> = match case.encoding {
            "" | "identity" => Box::new(body),
            "gzip" => Box::new(async_compression::tokio::bufread::GzipDecoder::new(
                tokio::io::BufReader::new(body),
            )),
            "deflate" => {
                let mut buffered = tokio::io::BufReader::new(body);
                // Same sniff the relay uses, so a raw-deflate body is decoded as raw deflate.
                let head = match buffered.fill_buf().await {
                    Ok(head) => head.to_vec(),
                    Err(_) => Vec::new(),
                };
                if is_zlib_stream(&head) {
                    Box::new(async_compression::tokio::bufread::ZlibDecoder::new(
                        buffered,
                    ))
                } else {
                    Box::new(async_compression::tokio::bufread::DeflateDecoder::new(
                        buffered,
                    ))
                }
            }
            other => return Err(format!("unknown encoding {other}")),
        };
        let mut reader = InjectingReader::new(reader, Injector::new(link.into_bytes()));
        let mut out = Vec::new();
        reader
            .read_to_end(&mut out)
            .await
            .map_err(|err| format!("inject: {err}"))?;
        Ok(Some(out))
    })
}

/// Replays the fixture, comparing bytes and decisions.
pub fn replay(document: &str) -> Result<usize, String> {
    let fixture: serde_json::Value =
        serde_json::from_str(document).map_err(|err| format!("parse the fixture: {err}"))?;
    let frozen = fixture["cases"]
        .as_array()
        .ok_or_else(|| "the fixture has no cases".to_string())?;
    let cases = cases();
    let expected = cases.len();
    if frozen.len() != expected {
        return Err(format!(
            "the fixture has {} cases, the corpus defines {}",
            frozen.len(),
            cases.len()
        ));
    }
    for (index, case) in cases.into_iter().enumerate() {
        let entry = &frozen[index];
        if entry["id"] != serde_json::json!(case.id) {
            return Err(format!("case {index} is not {}", case.id));
        }
        if entry["link"] != serde_json::json!(link_for(case.host)) {
            return Err(format!("{}: the injected link changed", case.id));
        }
        let decisions = serde_json::json!({
            "acceptsHtml": request_accepts_html(case.accept),
            "contentIsHtml": is_html(case.content_type),
        });
        if entry["decisions"] != decisions {
            return Err(format!(
                "{}: the header decisions changed: {}",
                case.id, entry["decisions"]
            ));
        }
        let body = unhex(
            entry["body"]
                .as_str()
                .ok_or_else(|| format!("{}: no body", case.id))?,
        )
        .ok_or_else(|| format!("{}: the body is not hex", case.id))?;
        let injected = inject(&case, &body)?;
        let produced = injected.as_deref().map(hex);
        let frozen_injected = entry["injected"].as_str().map(str::to_string);
        if produced != frozen_injected {
            return Err(format!(
                "{}: the injected bytes changed\nfrozen: {frozen_injected:?}\nnow:    {produced:?}",
                case.id
            ));
        }
    }
    Ok(expected)
}

fn runtime() -> tokio::runtime::Runtime {
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .expect("the corpus runtime builds")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_html_responses_are_rewritten() {
        let cases = cases();
        let plain = cases
            .iter()
            .find(|case| case.id == "plain-html")
            .expect("plain-html");
        let json = cases
            .iter()
            .find(|case| case.id == "non-html-passthrough")
            .expect("json");
        assert!(inject(plain, PAGE).expect("inject").is_some());
        assert!(inject(json, json.page).expect("inject").is_none());
    }

    #[test]
    fn the_link_carries_the_page_host() {
        assert_eq!(
            link_for("example.test"),
            r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css?h=example.test">"#
        );
    }

    #[test]
    fn a_raw_deflate_body_is_not_zlib() {
        let raw = encode_raw_deflate(PAGE).expect("deflate");
        assert!(!is_zlib_stream(&raw[..2]), "raw deflate has no zlib header");
        let zlib = encode("deflate", PAGE).expect("zlib");
        assert!(is_zlib_stream(&zlib[..2]), "zlib has a header");
    }

    #[test]
    fn the_corpus_bodies_fit_one_read() {
        for case in cases() {
            let body = match case.encoding {
                "gzip" => encode("gzip", case.page).expect("gzip"),
                "" | "identity" => case.page.to_vec(),
                _ => case.page.to_vec(),
            };
            assert!(
                body.len() < 16 * 1024,
                "{} is {} bytes, over the single-read assumption",
                case.id,
                body.len()
            );
        }
    }
}
