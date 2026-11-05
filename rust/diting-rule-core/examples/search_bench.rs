//! Rules-page search timings without the Dart/FFI round trip, so the native share of the
//! end-to-end number is separable.
//!
//! ```bash
//! cd rust && cargo run --release --example search_bench            # 100k rows
//! cargo run --release --example search_bench -- 200000
//! ```

use std::time::Instant;

use diting_rule_core::RuleSearchIndex;

const QUERIES: [&str; 6] = [
    "ads",
    "tracker",
    "example",
    ".com^",
    "analytics",
    "nothing-matches-this",
];

fn main() {
    let rows: usize = std::env::args()
        .nth(1)
        .and_then(|value| value.parse().ok())
        .unwrap_or(100_000);
    let patterns: Vec<String> = (0..rows).map(pattern_of).collect();
    let targets: Vec<Option<String>> = (0..rows)
        .map(|index| (index % 5 == 4).then(|| format!("10.0.{}.1", index % 256)))
        .collect();

    let mut build_micros = u64::MAX;
    let mut index = RuleSearchIndex::default();
    for _ in 0..3 {
        let started = Instant::now();
        let mut built = RuleSearchIndex::with_capacity(rows);
        for (pattern, target) in patterns.iter().zip(&targets) {
            built.push(pattern, target.as_deref());
        }
        build_micros = build_micros.min(started.elapsed().as_micros() as u64);
        index = built;
    }
    println!(
        "rows: {rows}, build: {:.1} ms (fold + store)",
        build_micros as f64 / 1000.0
    );

    let mut best_total = u64::MAX;
    let mut counts = Vec::new();
    for _ in 0..4 {
        let started = Instant::now();
        let mut hits = 0usize;
        counts.clear();
        for query in QUERIES {
            let matched = index.matching(query);
            hits += matched.len();
            counts.push(matched.len());
        }
        assert!(hits > 0);
        best_total = best_total.min(started.elapsed().as_micros() as u64);
    }
    println!(
        "scan: {:.2} ms/query over {} queries, hits {}",
        best_total as f64 / 1000.0 / QUERIES.len() as f64,
        QUERIES.len(),
        counts.iter().sum::<usize>()
    );
    for (query, count) in QUERIES.iter().zip(&counts) {
        println!("  {query:>20}: {count} hits");
    }
}

fn pattern_of(index: usize) -> String {
    match index % 5 {
        0 => format!("||ads{index}.example.com^"),
        1 => format!("||tracker{index}.analytics.net^"),
        2 => format!("0.0.0.0 metric{index}.example.org"),
        3 => format!("example{index}.com##.ad-banner"),
        _ => format!("||safe{index}.example.com^"),
    }
}
