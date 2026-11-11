//! DTRI compile timing, for comparing the Rust writer with the Kotlin/JVM reference.
//!
//! ```bash
//! # same corpus for both sides:
//! java rust/tools/dtri-reference/DTRIReference.java --generate 100000 /tmp/rules.txt
//! java rust/tools/dtri-reference/DTRIReference.java /tmp/rules.txt /tmp/ref.dtri
//! cargo run --release --example dtri_bench -- /tmp/rules.txt /tmp/rust.dtri
//!
//! # no corpus: synthetic 100k rules
//! cargo run --release --example dtri_bench
//! ```

use std::fs;
use std::time::Instant;

use diting_rule_core::dtri::{compile, Rule};

struct Owned {
    pattern: String,
    source: String,
    app_scope: Option<String>,
    app_inverted: bool,
    is_wildcard: bool,
    denyallow: Option<String>,
    is_regex: bool,
    dns_type: Option<String>,
}

fn parse_corpus(text: &str) -> Vec<Owned> {
    text.lines()
        .filter(|line| !line.is_empty())
        .map(|line| {
            let fields: Vec<&str> = line.split('\t').collect();
            let field = |index: usize| fields.get(index).copied().unwrap_or("");
            let optional = |index: usize| match fields.get(index).copied().unwrap_or("~") {
                "~" => None,
                value => Some(value.to_string()),
            };
            let flag = |index: usize| matches!(field(index), "1" | "true");
            Owned {
                pattern: field(0).to_string(),
                source: field(1).to_string(),
                app_scope: optional(3),
                app_inverted: flag(4),
                is_wildcard: flag(5),
                denyallow: optional(6),
                is_regex: flag(7),
                dns_type: optional(8),
            }
        })
        .collect()
}

fn synthetic(count: usize) -> Vec<Owned> {
    let second = [
        "ads", "track", "metrics", "cdn", "static", "promo", "beacon", "api",
    ];
    let tld = ["com", "net", "org", "io", "cn"];
    (0..count)
        .map(|index| Owned {
            pattern: format!(
                "||{}{}.{}{}.{}^",
                second[index % second.len()],
                index % 977,
                second[(index / 3) % second.len()],
                index % 53,
                tld[index % tld.len()]
            ),
            source: format!("sub_{}", 1 + index % 8),
            app_scope: None,
            app_inverted: false,
            is_wildcard: false,
            denyallow: None,
            is_regex: false,
            dns_type: None,
        })
        .collect()
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let owned = match args.get(1) {
        Some(path) => parse_corpus(&fs::read_to_string(path).expect("read corpus")),
        None => synthetic(100_000),
    };
    let rules: Vec<Rule<'_>> = owned
        .iter()
        .map(|rule| Rule {
            pattern: &rule.pattern,
            source: &rule.source,
            app_scope: rule.app_scope.as_deref(),
            app_inverted: rule.app_inverted,
            is_wildcard: rule.is_wildcard,
            denyallow: rule.denyallow.as_deref(),
            is_regex: rule.is_regex,
            dns_type: rule.dns_type.as_deref(),
        })
        .collect();

    let mut best = f64::MAX;
    let mut image = Vec::new();
    for _ in 0..3 {
        let started = Instant::now();
        image = compile(&rules);
        best = best.min(started.elapsed().as_secs_f64() * 1000.0);
    }
    if let Some(path) = args.get(2) {
        fs::write(path, &image).expect("write image");
    }
    println!(
        "rules={} imageBytes={} bestCompileMs={best:.1}",
        rules.len(),
        image.len()
    );
}
