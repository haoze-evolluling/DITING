//! Pure-Rust timing for the policy kernel: no cgo, no Go, no reason-string decoding.
//!
//! ```text
//! cargo run --release -p diting-policy-core --example policy_bench -- [snapshot.json | --synthetic N] [iterations]
//! ```
//!
//! `--synthetic 50000` builds the same shape (and the same query mix) as
//! `android/engine/policy_perf_test.go:largePolicySnapshotJSON`, so the numbers are directly
//! comparable with `go test -bench BenchmarkPolicyEvaluateGoWalkLarge`. Passing a real payload -
//! what the app sends to `ApplyRuleSnapshot` - measures the rules a device actually runs.

use std::sync::Arc;
use std::time::Instant;

use diting_policy_core::json::RuleSnapshot;
use diting_policy_core::Snapshot;

fn main() {
    let mut args = std::env::args().skip(1);
    let mut source = args.next().unwrap_or_else(|| "--synthetic".to_string());
    let mut rules = 50_000usize;
    if source == "--synthetic" {
        if let Some(value) = args.next() {
            rules = value.parse().unwrap_or(rules);
        }
    }
    let iterations: usize = args
        .next()
        .and_then(|value| value.parse().ok())
        .unwrap_or(50_000);

    let payload = if source == "--synthetic" {
        synthetic_snapshot(rules)
    } else {
        std::fs::read(&source).expect("read snapshot")
    };
    if source == "--synthetic" {
        source = format!("synthetic {rules} rules");
    }

    let started = Instant::now();
    let request = RuleSnapshot::parse(&payload).expect("parse snapshot");
    let (snapshot, regexes) = Snapshot::build(&request);
    let build = started.elapsed();
    let snapshot = Arc::new(snapshot);

    let queries = bench_domains(1024);
    for domain in &queries {
        std::hint::black_box(snapshot.evaluate(domain, "", 1));
    }
    let started = Instant::now();
    let mut blocked = 0usize;
    for i in 0..iterations {
        let decision = snapshot.evaluate(&queries[i % queries.len()], "", 1);
        blocked += usize::from(decision.blocked);
    }
    let elapsed = started.elapsed();
    println!("source: {source} (regex rules: {regexes})");
    println!("build: {build:?}");
    println!(
        "evaluate: {:.1} ns/op over {iterations} queries ({:.1}% blocked)",
        elapsed.as_nanos() as f64 / iterations as f64,
        blocked as f64 * 100.0 / iterations as f64
    );
}

/// `largePolicySnapshotJSON` in the Go benchmarks, minus the JSON round trip.
fn synthetic_snapshot(rules: usize) -> Vec<u8> {
    let mut block = Vec::new();
    for i in 0..rules {
        block.push(format!("ad{i}.tracker{}.com", i % 97));
    }
    for i in 0..(rules / 17) {
        block.push(format!("*.wc{i}.net"));
    }
    for i in 0..(rules / 100) {
        block.push(format!("ads{i}*.example.org"));
    }
    let mut allow = Vec::new();
    for i in 0..(rules / 250) {
        allow.push(format!("*.good{i}.org"));
    }
    let payload = serde_json::json!({
        "filterEnabled": true,
        "globalBlock": block,
        "globalAllow": allow,
        "appRules": {"com.example.app": {"block": ["*.appads.com", "x.appads.net"]}},
    });
    serde_json::to_vec(&payload).expect("serialize")
}

/// Same domain mix as `benchmarkDomains` in the Go benchmark.
fn bench_domains(count: usize) -> Vec<String> {
    (0..count)
        .map(|i| match i % 4 {
            0 => format!("img{i}.cdn.service{i}.com"),
            1 => format!("a.b.wc{i}.net"),
            2 => format!("ads{}.example.org", i % 600),
            _ => format!("api.app{i}.io"),
        })
        .collect()
}
