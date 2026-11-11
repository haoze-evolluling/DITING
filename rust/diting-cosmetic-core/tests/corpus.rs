//! Replays the golden corpus generated from the pre-migration Go implementation.
//!
//! `tests/fixtures/` was produced by `android/engine/mitm_cosmetic_inject.go` before the move, with a
//! scripted upstream that hands the reader one plan step at a time. Two cases the old code got wrong
//! are deliberately absent (see `rust/README.md`): a document with non-UTF-8 bytes before `<head`
//! panicked, and one with `İ` before it spliced the tag into the wrong place.

use std::fs;
use std::path::{Path, PathBuf};

use diting_cosmetic_core::host::{link_tag, normalize_host, query_escape};
use diting_cosmetic_core::inject::{Injector, Upstream, SCAN_LIMIT};

/// The host the engine serves the stylesheet from; `LocalAssetHost` in Go.
const ASSET_HOST: &str = "local.pwhs.app";

fn fixtures() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures")
}

/// Reads one TSV file, skipping the header row.
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

/// One planned upstream step, mirroring the generator's scripted reader.
#[derive(Debug)]
struct Step {
    size: usize,
    eof_after: bool,
    transient: bool,
    boom: bool,
    open: usize,
}

fn parse_plan(plan: &str) -> Vec<Step> {
    if plan.is_empty() {
        return Vec::new();
    }
    plan.split(',')
        .map(|raw| match raw {
            "~" => Step {
                size: 0,
                eof_after: false,
                transient: true,
                boom: false,
                open: 0,
            },
            "x" => Step {
                size: 0,
                eof_after: false,
                transient: false,
                boom: true,
                open: 0,
            },
            "!" => Step {
                size: 0,
                eof_after: true,
                transient: false,
                boom: false,
                open: 0,
            },
            sized => {
                let (text, eof_after) = match sized.strip_suffix('!') {
                    Some(head) => (head, true),
                    None => (sized, false),
                };
                Step {
                    size: text.parse().expect("plan size"),
                    eof_after,
                    transient: false,
                    boom: false,
                    open: 0,
                }
            }
        })
        .collect()
}

/// The scripted upstream: `(bytes delivered, what the read reported)`.
struct Script {
    document: Vec<u8>,
    steps: Vec<Step>,
}

impl Script {
    fn read(&mut self, capacity: usize) -> (Vec<u8>, Upstream) {
        let Some(step) = self.steps.first_mut() else {
            return (Vec::new(), Upstream::EOF);
        };
        if step.transient || step.boom {
            let boom = step.boom;
            self.steps.remove(0);
            let upstream = if boom {
                Upstream::FAILED
            } else {
                Upstream::NONE
            };
            return (Vec::new(), upstream);
        }
        let want = (step.size - step.open)
            .min(capacity)
            .min(self.document.len());
        let delivered: Vec<u8> = self.document.drain(..want).collect();
        step.open += delivered.len();
        let done = step.open >= step.size || self.document.is_empty();
        let eof_after = step.eof_after;
        if done {
            self.steps.remove(0);
        }
        let upstream = if done && eof_after {
            Upstream::EOF
        } else {
            Upstream::NONE
        };
        (delivered, upstream)
    }
}

fn encode_reads(reads: &[(usize, Upstream)]) -> String {
    reads
        .iter()
        .map(|(n, upstream)| {
            let kind = if upstream.eof {
                'e'
            } else if upstream.errored {
                'x'
            } else {
                'n'
            };
            format!("{n}{kind}")
        })
        .collect::<Vec<_>>()
        .join(",")
}

#[test]
fn injection_matches_the_old_streaming_scanner() {
    let cases = rows("inject.tsv");
    assert!(cases.len() >= 25, "corpus shrank to {} rows", cases.len());
    for row in cases {
        let name = &row[0];
        let document = blob(&row[1]);
        let plan = &row[2];
        let buffer_size: usize = row[3].parse().expect("buffer size");
        let host = &row[4];
        let want = blob(&row[5]);
        let want_reads = &row[6];

        let mut script = Script {
            document,
            steps: parse_plan(plan),
        };
        let mut injector = Injector::new(link_tag(host, ASSET_HOST).into_bytes());
        let mut buffer = vec![0u8; buffer_size];
        let mut out = Vec::new();
        let mut reads = Vec::new();

        for _ in 0..40 {
            if injector.pending_len() > 0 {
                let queued = injector.pending_into(&mut buffer);
                out.extend_from_slice(&buffer[..queued]);
                reads.push((queued, Upstream::NONE));
                continue;
            }
            let (chunk, upstream) = script.read(buffer.len());
            let n = chunk.len();
            buffer[..n].copy_from_slice(&chunk);
            let outcome = injector.process(&mut buffer, n, upstream);
            out.extend_from_slice(&buffer[..outcome.out_len]);
            reads.push((
                outcome.out_len,
                if outcome.keep_error {
                    upstream
                } else {
                    Upstream::NONE
                },
            ));
            if outcome.keep_error && upstream.errored {
                break;
            }
        }

        assert_eq!(
            out, want,
            "{name}: bytes differ (plan {plan}, buffer {buffer_size})"
        );
        assert_eq!(
            encode_reads(&reads),
            *want_reads,
            "{name}: the read sequence differs"
        );
    }
}

#[test]
fn scanning_limit_is_the_one_go_had() {
    assert_eq!(SCAN_LIMIT, 16 * 1024);
}

#[test]
fn host_normalization_matches_the_old_helper() {
    for row in rows("host.tsv") {
        let host = String::from_utf8(blob(&row[0])).expect("host is UTF-8 in the corpus");
        let want = String::from_utf8(blob(&row[1])).expect("normalized host is UTF-8");
        assert_eq!(normalize_host(&host), want, "host {host:?}");
    }
}

#[test]
fn link_tag_matches_the_old_helper() {
    for row in rows("link.tsv") {
        let host = String::from_utf8(blob(&row[0])).expect("host is UTF-8 in the corpus");
        let want = String::from_utf8(blob(&row[1])).expect("tag is UTF-8");
        assert_eq!(link_tag(&host, ASSET_HOST), want, "host {host:?}");
    }
}

#[test]
fn query_escape_is_url_query_escape() {
    let mut checked = 0;
    for row in rows("link.tsv") {
        let host = String::from_utf8(blob(&row[0])).expect("host is UTF-8 in the corpus");
        let tag = String::from_utf8(blob(&row[1])).expect("tag is UTF-8");
        let normalized = normalize_host(&host);
        if normalized.is_empty() {
            continue;
        }
        let escaped = query_escape(&normalized);
        assert!(tag.contains(&format!("?h={escaped}\"")), "host {host:?}");
        checked += 1;
    }
    assert!(checked > 20, "only {checked} hosts carried a query");
}

// --- the local asset server and the stylesheet (second migration, ABI 2) -----------------------

use diting_cosmetic_core::local::{is_asset_host, respond};
use diting_cosmetic_core::payload::{decode_response, decode_rules};
use diting_cosmetic_core::rules::host_suffixes;

/// Renders one response the way the fixture recorded it:
/// `status \0 content-type \0 name=value pairs \0 body`.
fn wire_response(payload: &diting_cosmetic_core::payload::ResponsePayload) -> Vec<u8> {
    let mut names: Vec<&(String, String)> = payload.headers.iter().collect();
    names.sort_by(|left, right| left.0.cmp(&right.0));
    let mut parts = vec![payload.status.to_string(), payload.content_type.clone()];
    for (name, value) in names {
        parts.push(format!("{name}={value}"));
    }
    parts.push(payload.body.clone());
    parts.join("\u{0}").into_bytes()
}

#[test]
fn the_stylesheet_corpus_replays_exactly() {
    let mut checked = 0;
    for row in rows("css.tsv") {
        let rules = decode_rules(&blob(&row[0])).expect("rule payload decodes");
        let host = String::from_utf8(blob(&row[1])).expect("host is UTF-8");
        let want = String::from_utf8(blob(&row[2])).expect("css is UTF-8");
        assert_eq!(rules.render(&host), want, "host {host:?}");
        checked += 1;
    }
    assert_eq!(checked, 135);
}

#[test]
fn the_suffix_corpus_replays_exactly() {
    let mut checked = 0;
    for row in rows("suffixes.tsv") {
        let host = String::from_utf8(blob(&row[0])).expect("host is UTF-8");
        let want = blob(&row[1]);
        let got = host_suffixes(&host).join("\u{0}").into_bytes();
        assert_eq!(got, want, "host {host:?}");
        checked += 1;
    }
    assert_eq!(checked, 15);
}

#[test]
fn the_asset_host_corpus_replays_exactly() {
    let mut checked = 0;
    for row in rows("asset_host.tsv") {
        let host = String::from_utf8(blob(&row[0])).expect("host is UTF-8");
        assert_eq!(is_asset_host(&host), row[1] == "true", "host {host:?}");
        checked += 1;
    }
    assert_eq!(checked, 13);
}

#[test]
fn the_route_corpus_replays_exactly() {
    let mut checked = 0;
    for row in rows("route.tsv") {
        assert_eq!(row.len(), 5, "row shape: {row:?}");
        let path = String::from_utf8(blob(&row[0])).expect("path is UTF-8");
        let host_query = String::from_utf8(blob(&row[1])).expect("host query is UTF-8");
        let payload_bytes: u64 = row[2].parse().expect("payload size");
        let rules = decode_rules(&blob(&row[3])).expect("rule payload decodes");
        let want = blob(&row[4]);

        let payload = decode_response(&diting_cosmetic_core::payload::encode_response(&respond(
            &path,
            &host_query,
            &rules,
            payload_bytes,
        )))
        .expect("response payload decodes");
        assert_eq!(
            wire_response(&payload),
            want,
            "path {path:?} host {host_query:?}"
        );
        checked += 1;
    }
    assert_eq!(checked, 120);
}
