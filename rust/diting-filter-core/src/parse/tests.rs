use super::*;

const CORPUS: &str = include_str!("../../tests/fixtures/parse_corpus.tsv");

struct Row {
    input: String,
    expected: String,
}

fn corpus() -> (Vec<Row>, String) {
    let mut rows = Vec::new();
    let mut document_expected = String::new();
    for line in CORPUS.split_terminator('\n') {
        let mut fields = line.splitn(3, '\t');
        let hex = fields.next().expect("hex field");
        let mode = fields.next().expect("mode field");
        let expected = fields.next().expect("expected field").to_string();
        if mode == "A" {
            document_expected = expected;
            continue;
        }
        assert_eq!(mode, "L", "unexpected corpus mode {mode}");
        rows.push(Row {
            input: decode_hex(hex),
            expected,
        });
    }
    (rows, document_expected)
}

fn decode_hex(hex: &str) -> String {
    let bytes = (0..hex.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&hex[index..index + 2], 16).expect("hex pair"))
        .collect::<Vec<u8>>();
    String::from_utf8(bytes).expect("corpus rows are UTF-8")
}

fn describe(line: &ParsedLine) -> String {
    format!(
        "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
        line.pattern,
        line.is_allow,
        line.important,
        line.is_regex,
        line.dns_type,
        line.is_wildcard,
        line.is_exact,
        line.deny_allow.join("~"),
        line.to.join("~"),
        u8::from(line.rewrite.is_some()),
    )
}

#[test]
fn single_lines_match_the_migrated_corpus() {
    let (rows, _) = corpus();
    assert!(rows.len() > 150, "corpus shrank to {} rows", rows.len());
    for row in &rows {
        let actual = match parse_line(&row.input) {
            Some(line) => describe(&line),
            None => "-".to_string(),
        };
        assert_eq!(actual, row.expected, "input {:?}", row.input);
    }
}

#[test]
fn a_document_is_its_lines_in_order() {
    let (rows, expected) = corpus();
    let text = rows
        .iter()
        .map(|row| row.input.as_str())
        .collect::<Vec<_>>()
        .join("\n")
        + "\n";

    let actual = parse_document(&text)
        .iter()
        .map(describe)
        .collect::<Vec<_>>()
        .join(" || ");
    assert_eq!(actual, expected);
}

#[test]
fn a_document_splits_lines_like_the_go_scanner() {
    let patterns = |text: &str| -> Vec<String> {
        parse_document(text)
            .iter()
            .map(|line| line.pattern.clone())
            .collect()
    };
    assert_eq!(patterns("||a.test^\r\n||b.test^\r\n"), ["a.test", "b.test"]);
    assert_eq!(patterns("||a.test^\n||b.test^"), ["a.test", "b.test"]);
    assert!(patterns("||a\rb.test^").is_empty());
}

#[test]
fn hosts_lines_expand_to_one_rule_per_name() {
    let parsed = parse_document("0.0.0.0 host1.com host2.com  host3.com # comment\n");
    let patterns: Vec<&str> = parsed.iter().map(|line| line.pattern.as_str()).collect();
    assert_eq!(patterns, ["host1.com", "host2.com", "host3.com"]);
    assert!(parsed
        .iter()
        .all(|line| line.raw == "0.0.0.0 host1.com host2.com  host3.com # comment"));
}

#[test]
fn rewrite_values_travel_back_raw() {
    let line = parse_line("||a.test^$dnsrewrite=NOERROR;TXT;Hello World").expect("parsed");
    assert_eq!(line.rewrite.as_deref(), Some("NOERROR;TXT;Hello World"));

    let bare = parse_line("@@||a.test^$dnsrewrite").expect("parsed");
    assert_eq!(bare.rewrite.as_deref(), Some(""));
    assert!(bare.is_allow);

    let comma =
        parse_line("||a.test^$dnsrewrite=NOERROR;HTTPS;1 . alpn=h3,h2,important").expect("parsed");
    assert_eq!(
        comma.rewrite.as_deref(),
        Some("NOERROR;HTTPS;1 . alpn=h3,h2")
    );
    assert!(comma.important);
}

#[test]
fn idn_patterns_come_back_as_a_labels() {
    for (input, expected) in [
        ("||bücher.example^", "xn--bcher-kva.example"),
        ("||BÜCHER.Example.^", "xn--bcher-kva.example"),
        ("||münchen.de^", "xn--mnchen-3ya.de"),
        ("||почта.рф^", "xn--80a1acny.xn--p1ai"),
        ("||中国.中国^", "xn--fiqs8s.xn--fiqs8s"),
        ("||straße.de^", "xn--strae-oqa.de"),
        ("||STRASSE.DE^", "strasse.de"),
    ] {
        let line = parse_line(input).unwrap_or_else(|| panic!("{input} should parse"));
        assert_eq!(line.pattern, expected, "{input}");
    }
}

#[test]
fn the_punycode_empty_label_is_rejected() {
    assert_eq!(parse_line("||xn--.test^"), None);
    assert_eq!(
        parse_line("||xn--bcher-kva.test^").map(|line| line.pattern),
        Some("xn--bcher-kva.test".to_string())
    );
}
