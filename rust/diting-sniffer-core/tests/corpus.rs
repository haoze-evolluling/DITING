//! Replays the corpus generated from the pre-migration Go implementation.
//!
//! `tests/fixtures/sni.tsv` and `http.tsv` were produced by `parseClientHelloSNI`,
//! `looksLikeHTTPRequest` and `parseHTTPHost` in `android/engine/mitm_sniffer.go` while those
//! functions were still the live implementation. Each file contains the hand-written cases plus
//! every prefix and a set of byte corruptions of one well-formed input, so truncation and clamped
//! lengths are pinned byte for byte.

use std::fs;
use std::path::{Path, PathBuf};

use diting_sniffer_core::http::{looks_like_http_request, parse_http_host};
use diting_sniffer_core::tls::parse_client_hello_sni;

fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

fn rows(name: &str) -> Vec<Vec<String>> {
    let text = fs::read_to_string(fixtures().join(name)).expect("fixture is readable");
    text.lines()
        .skip(1)
        .filter(|line| !line.is_empty())
        .map(|line| line.split('\t').map(str::to_string).collect())
        .collect()
}

/// `-` stands for "no bytes"; anything else is lower-case hex.
fn blob(text: &str) -> Vec<u8> {
    if text == "-" {
        return Vec::new();
    }
    (0..text.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&text[index..index + 2], 16).expect("hex"))
        .collect()
}

#[test]
fn sni_matches_the_old_parser() {
    let cases = rows("sni.tsv");
    assert!(cases.len() >= 100, "corpus shrank to {} rows", cases.len());
    for row in cases {
        let name = &row[0];
        let record = blob(&row[1]);
        let want = blob(&row[2]);
        assert_eq!(
            parse_client_hello_sni(&record),
            want.as_slice(),
            "{name}: sni differs"
        );
    }
}

#[test]
fn http_matches_the_old_sniffer() {
    let cases = rows("http.tsv");
    assert!(cases.len() >= 80, "corpus shrank to {} rows", cases.len());
    for row in cases {
        let name = &row[0];
        let request = blob(&row[1]);
        let want_looks = row[2] == "1";
        let want_host = blob(&row[3]);
        assert_eq!(
            looks_like_http_request(&request),
            want_looks,
            "{name}: looks_like_http_request differs"
        );
        assert_eq!(
            parse_http_host(&request),
            want_host.as_slice(),
            "{name}: Host differs"
        );
    }
}
