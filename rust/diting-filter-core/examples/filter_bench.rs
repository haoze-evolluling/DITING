//! Pure-Rust timing for the desktop rule index: no Go, no payload decoding.
//!
//! ```text
//! cargo run --release -p diting-filter-core --example filter_bench -- [rules] [iterations] [realistic]
//! ```
//!
//! The synthetic rule set and query mix mirror `rule_matcher_bench_test.go` (same rule families in
//! the same proportions, same `i % 5` domain mix), so the number here is the pure walk and the
//! difference to `go test -bench BenchmarkRuleMatcherMatch` is the C ABI crossing plus payload
//! decoding. Passing `realistic` switches to the production-like mix (99% plain domains, 1%
//! wildcards, 0.1% regexes), which is `BenchmarkRuleMatcherMatchRealistic` on the Go side.

use std::time::Instant;

use diting_filter_core::rule::{
    RewriteAction, Rule, FLAG_ALLOW, FLAG_REGEX, FLAG_REWRITE, FLAG_WILDCARD, RCODE_SUCCESS,
};
use diting_filter_core::FilterIndex;
use diting_go_compat::regex::compile_rule_regex;

fn main() {
    let mut args = std::env::args().skip(1);
    let rules: usize = args.next().and_then(|v| v.parse().ok()).unwrap_or(20_000);
    let iterations: usize = args.next().and_then(|v| v.parse().ok()).unwrap_or(200_000);
    let realistic = args.next().is_some_and(|mix| mix == "realistic");

    let rules = if realistic {
        rule_set_realistic(rules)
    } else {
        rule_set(rules)
    };
    let started = Instant::now();
    let index = FilterIndex::build(rules);
    let build = started.elapsed();

    let domains = domains(1024, index.total_rules() as usize);

    // Warm up one pass so the first iteration does not pay page faults for the whole index.
    for domain in domains.iter().take(256) {
        let _ = index.match_domain(domain, 1);
    }

    let started = Instant::now();
    let mut blocked = 0usize;
    for i in 0..iterations {
        let decision = index.match_domain(&domains[i % domains.len()], 1);
        if decision.action == diting_filter_core::Action::Block {
            blocked += 1;
        }
    }
    let elapsed = started.elapsed();

    println!("规则数: {}", index.total_rules());
    println!("构建: {:.1} ms", build.as_secs_f64() * 1000.0);
    println!(
        "匹配: {:.3} µs/查询（{} 次，{} 次命中拦截）",
        elapsed.as_secs_f64() * 1e6 / iterations as f64,
        iterations,
        blocked
    );
}

/// Same families and proportions as the Go benchmark: allow, wildcard, regex, `$dnstype`,
/// `$denyallow`, `$dnsrewrite`, plain block.
fn rule_set(size: usize) -> Vec<Rule> {
    let mut rules = Vec::with_capacity(size);
    for i in 0..size {
        rules.push(match i % 10 {
            0 => Rule::new(format!("allow{i}.example.com")).with_flags(FLAG_ALLOW),
            1 => {
                let pattern = format!("*.ads{i}.example.com");
                let mut rule = Rule::new(&pattern).with_flags(FLAG_WILDCARD);
                rule.regex = compile_rule_regex(&wildcard_source(&pattern)).ok();
                rule
            }
            2 => {
                let body = format!("^tracker[0-9]+\\.rx{i}\\.example\\.com$");
                let mut rule = Rule::new(&body).with_flags(FLAG_REGEX);
                rule.regex = compile_rule_regex(&format!("(?i){body}")).ok();
                rule
            }
            3 => Rule::new(format!("only{i}.example.com")).with_dns_type(28),
            4 => {
                let mut rule = Rule::new(format!("excluded{i}.example.com"));
                rule.deny_allow = vec![format!("cdn{i}.example.com")];
                rule
            }
            5 => {
                let mut rule = Rule::new(format!("rw{i}.example.com")).with_flags(FLAG_REWRITE);
                rule.rewrite = Some(RewriteAction {
                    bare: false,
                    rcode: RCODE_SUCCESS,
                    rrtype: 1,
                    key: "0;1;127.0.0.1".to_string(),
                });
                rule
            }
            _ => Rule::new(format!("blocked{i}.example.com")),
        });
    }
    rules
}

/// Production-like mix: almost everything is a plain domain.
fn rule_set_realistic(size: usize) -> Vec<Rule> {
    let mut rules = Vec::with_capacity(size);
    for i in 0..size {
        rules.push(if i % 1000 == 0 {
            let body = format!(r"^tracker[0-9]+\.rx{i}\.example\.com$");
            let mut rule = Rule::new(&body).with_flags(FLAG_REGEX);
            rule.regex = compile_rule_regex(&format!("(?i){body}")).ok();
            rule
        } else if i % 100 == 1 {
            let pattern = format!("*.ads{i}.example.com");
            let mut rule = Rule::new(&pattern).with_flags(FLAG_WILDCARD);
            rule.regex = compile_rule_regex(&wildcard_source(&pattern)).ok();
            rule
        } else if i % 50 == 2 {
            Rule::new(format!("allow{i}.example.com")).with_flags(FLAG_ALLOW)
        } else {
            Rule::new(format!("blocked{i}.example.com"))
        });
    }
    rules
}

/// The same `i % 5` mix of clean / trie / wildcard / regex / rewrite queries as the Go benchmark.
fn domains(size: usize, rules: usize) -> Vec<String> {
    let mut domains = Vec::with_capacity(size);
    for i in 0..size {
        let index = (i * 7) % rules;
        domains.push(match i % 5 {
            0 => format!("clean{i}.other.example.net"),
            1 => format!("sub.blocked{index}.example.com"),
            2 => format!("x.ads{index}.example.com"),
            3 => format!("tracker{i}.rx{index}.example.com"),
            _ => format!("rw{index}.example.com"),
        });
    }
    domains
}

/// `buildWildcardRegex` from the Go parser, reproduced for the synthetic set.
fn wildcard_source(pattern: &str) -> String {
    let mut source = String::from("(?i)^(?:.*\\.)?");
    for ch in pattern.chars() {
        if ch == '*' {
            source.push_str(".*");
        } else {
            source.push_str(&regex::escape(&ch.to_string()));
        }
    }
    source.push('$');
    source
}
