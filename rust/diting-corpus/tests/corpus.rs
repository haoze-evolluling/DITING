use std::fs;

use diting_corpus::{contract, dns, fixture_dir, mitm, tun};

fn fixture(name: &str) -> Vec<u8> {
    let path = fixture_dir().join(name);
    fs::read(&path).unwrap_or_else(|err| panic!("cannot read {}: {err}", path.display()))
}

fn fixture_text(name: &str) -> String {
    String::from_utf8(fixture(name)).expect("the fixture is UTF-8")
}

#[test]
fn fixtures_are_current() {
    assert_eq!(
        fixture_text("dns_answers.json"),
        dns::build(),
        "dns_answers.json is stale: run `cargo run -p diting-corpus --bin gen-corpus`"
    );
    assert_eq!(
        fixture_text("contract_documents.json"),
        contract::build(),
        "contract_documents.json is stale: run `cargo run -p diting-corpus --bin gen-corpus`"
    );
    assert_eq!(
        fixture("tun_flows.pcap"),
        tun::pcap(),
        "tun_flows.pcap is stale: run `cargo run -p diting-corpus --bin gen-corpus`"
    );
    assert_eq!(
        fixture_text("mitm_exchanges.json"),
        mitm::build(),
        "mitm_exchanges.json is stale: run `cargo run -p diting-corpus --bin gen-corpus`"
    );
}

#[test]
fn the_dns_corpus_replays() {
    let document = fixture_text("dns_answers.json");
    let cases = dns::replay(&document).expect("the DNS corpus replays");
    assert!(cases >= 10, "the corpus covers {cases} cases");
}

#[test]
fn the_contract_corpus_replays() {
    let document = fixture_text("contract_documents.json");
    contract::replay(&document).expect("the contract corpus replays");
}

#[test]
fn the_tun_corpus_replays_through_the_transparent_proxy() {
    let bytes = fixture("tun_flows.pcap");
    let packets = tun::replay(&bytes).expect("the capture replays through the netstack");
    assert_eq!(packets, 6);
}

#[test]
fn the_mitm_corpus_replays() {
    let document = fixture_text("mitm_exchanges.json");
    let cases = mitm::replay(&document).expect("the MITM corpus replays");
    assert_eq!(cases, 6);
}
