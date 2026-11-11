//! The DNS corpus: synthesized answers and the decoded view of a query/answer pair.
//!
//! `android/engine/dns_packet.go` + `dns_blocks.go` built every synthesized answer with `dns.Msg` and
//! `dns.NewRR`; those builders now live in [`diting_dns_core::reply`], and the engine's callers only
//! pick a plan and write the bytes. The corpus therefore freezes two things at once:
//!
//! * the **plan** the engine selects for a query (`block:<mode>`, `rewrite-ip`, `rewrite-cname`,
//!   `local-asset`, `ddr`, `servfail`), which is the behaviour a future refactor could silently
//!   change;
//! * the **bytes** `reply::render` produces, including the transaction id, the `RA` bit and the answer
//!   TTLs, because a Kotlin-visible resolver answer is compared by clients, not by us.
//!
//! The decoded view (`query_info`, `validate`, `extract`) is frozen next to the bytes: those are the
//! functions the engine uses for logging, cache admission and the null-block verdict, and their
//! numeric status codes are a wire contract with the Go code that is being deleted.

use serde_json::json;

use diting_dns_core::message;
use diting_dns_core::reply::{self, ReplyPlan};
use diting_dns_wire::{parse_answer_records, parse_header, parse_response};

use crate::hex;

/// One corpus case: a query plus the plan the engine picks for it.
pub struct Case {
    pub id: &'static str,
    pub name: &'static str,
    pub qtype: u16,
    pub plan: Plan,
}

/// The plans the engine can produce for a single query, named the way the fixture spells them.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Plan {
    /// `standaloneBlock` with one of `RESPONSE_*`.
    Block(u8),
    RewriteIp(&'static str),
    RewriteCname(&'static str),
    LocalAsset,
    Ddr,
    Servfail,
}

impl Plan {
    pub fn label(self) -> String {
        match self {
            Plan::Block(mode) => format!("block:{mode}"),
            Plan::RewriteIp(ip) => format!("rewrite-ip:{ip}"),
            Plan::RewriteCname(target) => format!("rewrite-cname:{target}"),
            Plan::LocalAsset => "local-asset".to_string(),
            Plan::Ddr => "ddr".to_string(),
            Plan::Servfail => "servfail".to_string(),
        }
    }
}

/// The cases, in the order the fixture lists them.
pub fn cases() -> Vec<Case> {
    vec![
        Case {
            id: "block-custom-ip-a",
            name: "ads.example.com",
            qtype: 1,
            plan: Plan::Block(reply::RESPONSE_CUSTOM_IP),
        },
        Case {
            id: "block-custom-ip-aaaa",
            name: "ads.example.com",
            qtype: 28,
            plan: Plan::Block(reply::RESPONSE_CUSTOM_IP),
        },
        Case {
            id: "block-nxdomain-a",
            name: "tracker.example.net",
            qtype: 1,
            plan: Plan::Block(reply::RESPONSE_NXDOMAIN),
        },
        Case {
            id: "block-refused-a",
            name: "tracker.example.net",
            qtype: 1,
            plan: Plan::Block(reply::RESPONSE_REFUSED),
        },
        Case {
            id: "block-nodata-a",
            name: "tracker.example.net",
            qtype: 1,
            plan: Plan::Block(reply::RESPONSE_NO_DATA),
        },
        Case {
            id: "rewrite-ipv4",
            name: "pinned.example.org",
            qtype: 1,
            plan: Plan::RewriteIp("9.8.7.6"),
        },
        Case {
            id: "rewrite-cname",
            name: "alias.example.org",
            qtype: 1,
            plan: Plan::RewriteCname("edge.example.net"),
        },
        Case {
            id: "local-asset",
            name: "local.pwhs.app",
            qtype: 1,
            plan: Plan::LocalAsset,
        },
        Case {
            id: "ddr",
            name: "_dns.resolver.arpa",
            qtype: 1,
            plan: Plan::Ddr,
        },
        Case {
            id: "servfail",
            name: "broken.example.test",
            qtype: 1,
            plan: Plan::Servfail,
        },
        Case {
            id: "query-txt",
            name: "notes.example.test",
            qtype: 16,
            plan: Plan::Block(reply::RESPONSE_NO_DATA),
        },
    ]
}

/// The transaction id every query in the corpus uses, so the answers are comparable byte for byte.
pub const QUERY_ID: u16 = 0x1234;

/// A query wire: header (RD set, one question) + `name` + `qtype` + class IN.
pub fn query(name: &str, qtype: u16) -> Vec<u8> {
    let mut wire = Vec::with_capacity(64);
    wire.extend_from_slice(&QUERY_ID.to_be_bytes());
    wire.extend_from_slice(&0x0100u16.to_be_bytes()); // RD
    wire.extend_from_slice(&1u16.to_be_bytes()); // QDCOUNT
    wire.extend_from_slice(&0u16.to_be_bytes()); // ANCOUNT
    wire.extend_from_slice(&0u16.to_be_bytes()); // NSCOUNT
    wire.extend_from_slice(&0u16.to_be_bytes()); // ARCOUNT
    assert!(
        diting_dns_wire::pack_name(name, &mut wire),
        "the corpus names are valid"
    );
    wire.extend_from_slice(&qtype.to_be_bytes());
    wire.extend_from_slice(&1u16.to_be_bytes());
    wire
}

/// A synthetic upstream answer for `query_wire`: `QR|RD|RA`, one A record per address.
///
/// Used for the rewrite-CNAME case and for the `validate`/`extract` views; the point is a *well
/// formed* answer, not a real one.
pub fn upstream_answer(query_wire: &[u8], addresses: &[[u8; 4]]) -> Vec<u8> {
    let question = question_section(query_wire).expect("the corpus queries carry a question");
    let mut wire = Vec::with_capacity(question.len() + 16 * addresses.len() + 12);
    wire.extend_from_slice(&query_wire[..2]); // the same transaction id
    wire.extend_from_slice(&0x8180u16.to_be_bytes()); // QR | RD | RA, NOERROR
    wire.extend_from_slice(&1u16.to_be_bytes()); // QDCOUNT
    wire.extend_from_slice(&(addresses.len() as u16).to_be_bytes());
    wire.extend_from_slice(&0u16.to_be_bytes());
    wire.extend_from_slice(&0u16.to_be_bytes());
    wire.extend_from_slice(&question);
    for address in addresses {
        wire.extend_from_slice(&0xc00cu16.to_be_bytes()); // a pointer to the question name
        wire.extend_from_slice(&1u16.to_be_bytes()); // TYPE A
        wire.extend_from_slice(&1u16.to_be_bytes()); // CLASS IN
        wire.extend_from_slice(&300u32.to_be_bytes()); // TTL
        wire.extend_from_slice(&4u16.to_be_bytes()); // RDLENGTH
        wire.extend_from_slice(address);
    }
    wire
}

/// The question section of a query (`name` + type + class), without the 12-byte header.
fn question_section(query_wire: &[u8]) -> Option<Vec<u8>> {
    let name_len = name_wire_len(&query_wire[12..])?;
    let end = 12 + name_len + 4;
    query_wire.get(12..end).map(|section| section.to_vec())
}

fn name_wire_len(bytes: &[u8]) -> Option<usize> {
    let mut offset = 0;
    loop {
        let length = *bytes.get(offset)? as usize;
        offset += 1;
        if length == 0 {
            return Some(offset);
        }
        offset += length;
    }
}

/// Runs `plan` over `query_wire`; `resolved` is the synthetic answer the CNAME rewrite consumes.
pub fn build_plan(plan: Plan, query_wire: &[u8], resolved: &[u8]) -> Option<ReplyPlan> {
    match plan {
        Plan::Block(mode) => reply::block(query_wire, mode),
        Plan::RewriteIp(ip) => reply::rewrite_ip(query_wire, ip),
        Plan::RewriteCname(target) => reply::rewrite_cname(query_wire, target, resolved),
        Plan::LocalAsset => reply::local_asset(query_wire),
        Plan::Ddr => reply::ddr(query_wire),
        Plan::Servfail => reply::servfail(query_wire),
    }
}

/// Builds the whole fixture document.
pub fn build() -> String {
    let cases: Vec<serde_json::Value> = cases()
        .into_iter()
        .map(|case| {
            let query_wire = query(case.name, case.qtype);
            // Every case gets the same synthetic upstream answer; only the CNAME rewrite reads it.
            let resolved = upstream_answer(&query_wire, &[[1, 2, 3, 4]]);
            let plan = build_plan(case.plan, &query_wire, &resolved)
                .expect("every corpus case produces a plan");
            let rendered = if plan.is_not_applicable() {
                None
            } else {
                reply::render(&query_wire, &plan)
            };
            // `render` output is itself re-parsed, so the fixture records the decoded view too.
            let decoded = rendered.as_deref().and_then(parse_response);
            let answers = rendered
                .as_deref()
                .and_then(parse_answer_records)
                .unwrap_or_default();
            json!({
                "id": case.id,
                "name": case.name,
                "qtype": case.qtype,
                "plan": case.plan.label(),
                "query": hex(&query_wire),
                "queryInfo": query_info_json(&query_wire),
                "resolved": hex(&resolved),
                "response": rendered.as_deref().map(hex),
                "rcode": decoded.as_ref().map(|meta| meta.rcode),
                "recursionAvailable": rendered.as_deref().and_then(recursion_available),
                "answers": answers
                    .iter()
                    .map(|record| json!({"type": record.rrtype, "ttl": record.ttl, "rdata": hex(&record.rdata)}))
                    .collect::<Vec<_>>(),
                "validate": validation_json(&query_wire, &resolved),
                "extract": extract_json(&resolved),
            })
        })
        .collect();

    json!({
        "note": "Stage 0 DNS corpus: synthesized answers and the decoded query/answer view. \
                 Generated by `cargo run -p diting-corpus --bin gen-corpus`; the producers are \
                 diting-dns-core::reply and diting-dns-core::message.",
        "cases": cases,
    })
    .to_string()
}

/// Replays the fixture; `Ok(cases)` or the first mismatch.
pub fn replay(document: &str) -> Result<usize, String> {
    let fixture: serde_json::Value =
        serde_json::from_str(document).map_err(|err| format!("parse the fixture: {err}"))?;
    let frozen_cases = fixture["cases"]
        .as_array()
        .ok_or_else(|| "the fixture has no cases".to_string())?;
    let expected = cases().len();
    if frozen_cases.len() != expected {
        return Err(format!(
            "the fixture has {} cases, the corpus defines {expected}",
            frozen_cases.len()
        ));
    }

    for (index, case) in cases().into_iter().enumerate() {
        let frozen = &frozen_cases[index];
        let id = case.id;
        if frozen["id"] != json!(id) {
            return Err(format!("case {index} is not {id}"));
        }
        let query_wire = crate::unhex(
            frozen["query"]
                .as_str()
                .ok_or_else(|| format!("{id}: no query"))?,
        )
        .ok_or_else(|| format!("{id}: query is not hex"))?;
        if query_wire != query(case.name, case.qtype) {
            return Err(format!("{id}: the frozen query bytes changed"));
        }
        let resolved = crate::unhex(
            frozen["resolved"]
                .as_str()
                .ok_or_else(|| format!("{id}: no resolved answer"))?,
        )
        .ok_or_else(|| format!("{id}: resolved is not hex"))?;

        if frozen["queryInfo"] != query_info_json(&query_wire) {
            return Err(format!("{id}: queryInfo changed: {}", frozen["queryInfo"]));
        }
        if frozen["validate"] != validation_json(&query_wire, &resolved) {
            return Err(format!("{id}: validate changed: {}", frozen["validate"]));
        }
        if frozen["extract"] != extract_json(&resolved) {
            return Err(format!("{id}: extract changed: {}", frozen["extract"]));
        }

        let plan = build_plan(case.plan, &query_wire, &resolved)
            .ok_or_else(|| format!("{id}: the plan is no longer produced"))?;
        let rendered = if plan.is_not_applicable() {
            None
        } else {
            reply::render(&query_wire, &plan)
        };
        let frozen_response = frozen["response"].as_str().map(str::to_string);
        let produced = rendered.as_deref().map(hex);
        if frozen_response != produced {
            return Err(format!(
                "{id}: the answer bytes changed\nfrozen: {frozen_response:?}\nnow:    {produced:?}"
            ));
        }

        let decoded = rendered.as_deref().and_then(parse_response);
        if frozen["rcode"] != json!(decoded.as_ref().map(|meta| meta.rcode)) {
            return Err(format!("{id}: the rcode changed: {}", frozen["rcode"]));
        }
        if frozen["recursionAvailable"] != json!(rendered.as_deref().and_then(recursion_available))
        {
            return Err(format!(
                "{id}: the RA bit changed: {}",
                frozen["recursionAvailable"]
            ));
        }
        let answers: Vec<serde_json::Value> = rendered
            .as_deref()
            .and_then(parse_answer_records)
            .unwrap_or_default()
            .iter()
            .map(|record| {
                json!({"type": record.rrtype, "ttl": record.ttl, "rdata": hex(&record.rdata)})
            })
            .collect();
        if frozen["answers"] != json!(answers) {
            return Err(format!("{id}: the answers changed: {}", frozen["answers"]));
        }
    }
    Ok(expected)
}

fn query_info_json(query_wire: &[u8]) -> serde_json::Value {
    let info = message::query_info(query_wire);
    json!({"name": info.name, "qtype": info.qtype, "valid": info.valid})
}

fn validation_json(query_wire: &[u8], response: &[u8]) -> serde_json::Value {
    let validation = message::validate(query_wire, response);
    json!({"status": validation.status, "rcode": validation.rcode})
}

fn extract_json(response: &[u8]) -> serde_json::Value {
    match message::extract(response) {
        Some(extracted) => json!({
            "rcode": extracted.rcode,
            "blocked": extracted.blocked,
            "questionName": extracted.question_name,
            "addresses": extracted
                .addresses
                .iter()
                .map(|record| json!({"type": record.rrtype, "ttl": record.ttl, "address": hex(&record.address)}))
                .collect::<Vec<_>>(),
            "chainTargets": extracted
                .chain_targets
                .iter()
                .map(|target| format!("{:?}:{}", target.kind, target.domain))
                .collect::<Vec<_>>(),
            "ips": extracted.ips,
            "resolvedIps": extracted.resolved_ips,
        }),
        None => json!(null),
    }
}

/// The header's rcode for a rendered answer, for callers that do not want the whole meta.
pub fn rcode_of(response: &[u8]) -> Option<u16> {
    parse_header(response).map(|header| header.flags & 0x000f)
}

/// The `RA` bit of a rendered answer. `ResponseMeta` does not carry it (the cache never needed it),
/// and it is part of the synthesized answers the clients see: only the rewrite path sets it.
pub fn recursion_available(response: &[u8]) -> Option<bool> {
    parse_header(response).map(|header| header.flags & 0x0080 != 0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::unhex;

    #[test]
    fn the_query_builder_matches_the_expected_wire_shape() {
        let wire = query("a.example", 1);
        assert_eq!(&wire[..2], &QUERY_ID.to_be_bytes());
        let info = message::query_info(&wire);
        assert_eq!(info.name, "a.example");
        assert_eq!(info.qtype, 1);
        assert!(info.valid);
    }

    #[test]
    fn a_synthetic_answer_holds_the_address_it_was_built_with() {
        let query_wire = query("a.example", 1);
        let answer = upstream_answer(&query_wire, &[[9, 8, 7, 6]]);
        let extracted = message::extract(&answer).expect("the answer parses");
        assert_eq!(extracted.ips, vec!["9.8.7.6".to_string()]);
        assert!(!extracted.blocked);
        assert_eq!(rcode_of(&answer), Some(0));
        // The validator accepts it: same question, not a null block.
        assert_eq!(message::validate(&query_wire, &answer).status, 0);
    }

    #[test]
    fn a_null_answer_is_recognised_as_blocked() {
        let query_wire = query("a.example", 1);
        let answer = upstream_answer(&query_wire, &[[0, 0, 0, 0]]);
        assert!(message::extract(&answer).expect("parses").blocked);
    }

    #[test]
    fn every_case_produces_a_plan() {
        for case in cases() {
            let query_wire = query(case.name, case.qtype);
            let resolved = upstream_answer(&query_wire, &[[1, 2, 3, 4]]);
            let plan = build_plan(case.plan, &query_wire, &resolved)
                .unwrap_or_else(|| panic!("{} produced no plan", case.id));
            if case.id != "rewrite-cname" {
                assert!(!plan.is_not_applicable(), "{} is not applicable", case.id);
            }
        }
    }

    #[test]
    fn unhex_and_hex_agree_with_the_fixture_encoding() {
        let wire = query("x.test", 28);
        assert_eq!(unhex(&hex(&wire)), Some(wire));
    }
}
