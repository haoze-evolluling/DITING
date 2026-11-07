//! The migration corpus: every row was produced by running the Go implementation that this crate
//! replaced (`internal/core/zz_hosts_fixture_gen_test.go`, deleted with the Go parser).
//!
//! Rows are `kind`, `case`, `arg`, `expect`:
//! * `addr` — one hosts address field: strip the zone, parse, collapse
//! * `arpa` — one reverse name through `ParseIPFromArpa`
//! * `has` — `HasDomain` on the parsed case
//! * `lookup` — `Lookup` for one qtype (`arg` is `host|qtype`)
//! * `ptr` — `LookupPTR` for one reverse name
//!
//! Addresses are written as `4:<hex>` / `16:<hex>` / `none`; lists are comma separated.

use std::path::{Path, PathBuf};

use diting_hosts_core::hosts::{HostsTable, TYPE_A, TYPE_AAAA};
use diting_hosts_core::{parse_arpa, parse_hosts_address, Addr};

fn fixture_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests")
        .join("fixtures")
}

fn describe(addr: &Addr) -> String {
    format!("{}:{}", addr.width(), hex(addr.as_bytes()))
}

fn hex(bytes: &[u8]) -> String {
    let mut out = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        out.push_str(&format!("{byte:02x}"));
    }
    out
}

fn describe_list(addresses: &[Addr]) -> String {
    if addresses.is_empty() {
        return "-".to_string();
    }
    addresses.iter().map(describe).collect::<Vec<_>>().join(",")
}

fn compare(expect: &str, got: &str) -> bool {
    match expect {
        "none" => got == "none",
        _ => got == expect,
    }
}

fn parse_expect(expect: &str) -> Option<Addr> {
    if expect == "none" {
        return None;
    }
    let (width, bytes) = expect.split_once(':').expect("width:hex");
    let mut raw = Vec::with_capacity(bytes.len() / 2);
    let chars: Vec<char> = bytes.chars().collect();
    for pair in chars.chunks(2) {
        raw.push(u8::from_str_radix(&pair.iter().collect::<String>(), 16).expect("hex"));
    }
    assert_eq!(raw.len(), width.parse::<usize>().expect("width"));
    Addr::from_bytes(&raw)
}

/// `strings.Fields` on the case name gives the file to parse.
fn table_for(case: &str) -> HostsTable {
    let path = fixture_dir().join(format!("case_{case}.hosts"));
    HostsTable::build(&[diting_hosts_core::Source::File(path)])
}

#[test]
fn corpus_matches_the_go_implementation() {
    let text =
        std::fs::read_to_string(fixture_dir().join("expectations.tsv")).expect("expectations");
    let mut checked = 0usize;
    let mut tables: Vec<(String, HostsTable)> = Vec::new();

    for line in text.lines() {
        if line.starts_with('#') || line.is_empty() {
            continue;
        }
        let fields: Vec<&str> = line.split('\t').collect();
        assert_eq!(fields.len(), 4, "row: {line}");
        let (kind, case, arg, expect) = (fields[0], fields[1], fields[2], fields[3]);
        match kind {
            "addr" => {
                let got = match parse_hosts_address(arg) {
                    Some(addr) => describe(&addr),
                    None => "none".to_string(),
                };
                assert!(
                    compare(expect, &got),
                    "addr {arg}: got {got}, want {expect}"
                );
            }
            "arpa" => {
                let got = match parse_arpa(arg) {
                    Some(addr) => describe(&addr),
                    None => "none".to_string(),
                };
                assert!(
                    compare(expect, &got),
                    "arpa {arg}: got {got}, want {expect}"
                );
                // The payload carries the same answer for the Go side.
                if let Some(expected) = parse_expect(expect) {
                    assert_eq!(parse_arpa(arg), Some(expected), "arpa {arg} address");
                }
            }
            "has" => {
                let table = case_table(&mut tables, case);
                assert_eq!(
                    table.has_domain(arg).to_string(),
                    expect,
                    "has {case} {arg}"
                );
            }
            "lookup" => {
                let (host, qtype) = arg.rsplit_once('|').expect("host|qtype");
                let qtype = qtype.parse::<u16>().expect("qtype");
                assert!(qtype == TYPE_A || qtype == TYPE_AAAA);
                let table = case_table(&mut tables, case);
                let got = describe_list(&table.lookup(host, qtype));
                assert!(
                    compare(expect, &got),
                    "lookup {case} {arg}: got {got}, want {expect}"
                );
            }
            "ptr" => {
                let table = case_table(&mut tables, case);
                let names = table.ptr(arg);
                let got = if names.is_empty() {
                    "-".to_string()
                } else {
                    names.join(",")
                };
                assert!(
                    compare(expect, &got),
                    "ptr {case} {arg}: got {got}, want {expect}"
                );
                // The same alias set is what `LookupReverse` sees first.
                if let Some(first) = names.first() {
                    let addr = parse_arpa(arg).expect("address");
                    assert_eq!(table.reverse(&addr), Some(first.as_str()));
                }
            }
            other => panic!("unknown row kind {other}"),
        }
        checked += 1;
    }

    assert!(checked > 100, "only {checked} rows checked");
}

fn case_table<'a>(tables: &'a mut Vec<(String, HostsTable)>, case: &str) -> &'a HostsTable {
    if let Some(index) = tables.iter().position(|(name, _)| name == case) {
        return &tables[index].1;
    }
    tables.push((case.to_string(), table_for(case)));
    let index = tables.len() - 1;
    &tables[index].1
}
