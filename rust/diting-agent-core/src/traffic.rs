//! The two real log tables folded into the numbers the traffic prompt shows the model.
//!
//! Aggregation and the rendered section live together because the prompt says exactly what the
//! counters mean ("缓存命中" is `cached = 1`, not "answered from cache"), and splitting them across
//! languages is how those two drift.

use std::cmp::Ordering;

/// One `dns_log` row, reduced to the three fields the summary reads.
pub struct DnsRow {
    pub domain: String,
    pub result: String,
    pub cached: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Summary {
    pub dns_samples: u32,
    pub blocked_dns: u32,
    pub rewritten_dns: u32,
    pub cached_dns: u32,
    /// Highest request counts first; ties on the domain so two runs of the same rows agree.
    pub top_domains: Vec<(String, u32)>,
    pub http_samples: u32,
    pub blocked_http: u32,
    pub bypassed_http: u32,
    /// `Some` when this mode has no HTTPS surface at all (express), or the table is missing.
    pub unavailable_reason: Option<String>,
}

/// Eight is the prompt's budget: more rows push the actual instructions out of the model's window.
const TOP_DOMAINS: usize = 8;

impl Summary {
    pub fn is_empty(&self) -> bool {
        self.dns_samples == 0 && self.http_samples == 0
    }

    /// Text for the model. Empty data says "no records" instead of omitting the section, which
    /// would read as "nothing mentioned means nothing wrong".
    pub fn render(&self) -> String {
        let mut out = String::with_capacity(512);
        out.push_str("【近期 DNS 监控统计】\n");
        out.push_str(&format!("- 采样数量: {} 条\n", self.dns_samples));
        out.push_str(&format!(
            "- 规则拦截: {} 条, 规则覆写: {} 条, 缓存命中: {} 条\n",
            self.blocked_dns, self.rewritten_dns, self.cached_dns
        ));
        if self.top_domains.is_empty() {
            out.push_str("- 高频请求域名: 采样窗口内没有任何 DNS 记录\n");
        } else {
            out.push_str("- 高频请求域名:\n");
            for (domain, count) in &self.top_domains {
                out.push_str(&format!("  * {domain} (请求 {count} 次)\n"));
            }
        }
        out.push('\n');
        out.push_str("【近期 HTTP/HTTPS 流量统计】\n");
        match (&self.unavailable_reason, self.http_samples) {
            (Some(reason), _) => {
                out.push_str(&format!("- 本工作模式没有 HTTPS 检查面：{reason}\n"));
            }
            (None, 0) => {
                out.push_str("- 采样数量: 0 条（未装/未信任 CA 时不产生此类记录）\n");
            }
            (None, samples) => {
                out.push_str(&format!(
                    "- 采样数量: {samples} 条, 拦截数: {}, 旁路直连数: {}\n",
                    self.blocked_http, self.bypassed_http
                ));
            }
        }
        out.trim_end().to_string()
    }
}

/// `String.compareTo` in Dart/JVM compares UTF-16 code units, which is not the UTF-8 byte order for
/// astral characters; domain names are usually ASCII, but a Chinese or emoji host must not reorder.
fn compare_utf16(left: &str, right: &str) -> Ordering {
    let mut left_units = left.encode_utf16();
    let mut right_units = right.encode_utf16();
    loop {
        match (left_units.next(), right_units.next()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(left_unit), Some(right_unit)) => match left_unit.cmp(&right_unit) {
                Ordering::Equal => continue,
                other => return other,
            },
        }
    }
}

/// `result` is compared case-insensitively, exactly like the Dart original (`toUpperCase`).
pub fn summarize(dns: &[DnsRow], http_outcomes: &[String], unavailable: Option<String>) -> Summary {
    let mut counts: Vec<(String, u32)> = Vec::new();
    let mut blocked = 0u32;
    let mut rewritten = 0u32;
    let mut cached = 0u32;
    for row in dns {
        match counts.iter_mut().find(|(domain, _)| domain == &row.domain) {
            Some((_, count)) => *count += 1,
            None => counts.push((row.domain.clone(), 1)),
        }
        let result = row.result.to_uppercase();
        if result == "BLOCKED" {
            blocked += 1;
        }
        if result == "REWRITTEN" {
            rewritten += 1;
        }
        if row.cached {
            cached += 1;
        }
    }
    counts.sort_by(|left, right| match right.1.cmp(&left.1) {
        Ordering::Equal => compare_utf16(&left.0, &right.0),
        other => other,
    });
    counts.truncate(TOP_DOMAINS);

    let mut blocked_http = 0u32;
    let mut bypassed_http = 0u32;
    for outcome in http_outcomes {
        let outcome = outcome.to_lowercase();
        if outcome == "blocked" {
            blocked_http += 1;
        }
        if outcome == "passthrough" || outcome == "bypassed" {
            bypassed_http += 1;
        }
    }

    Summary {
        dns_samples: dns.len() as u32,
        blocked_dns: blocked,
        rewritten_dns: rewritten,
        cached_dns: cached,
        top_domains: counts,
        http_samples: http_outcomes.len() as u32,
        blocked_http,
        bypassed_http,
        unavailable_reason: unavailable,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(domain: &str, result: &str, cached: bool) -> DnsRow {
        DnsRow {
            domain: domain.to_string(),
            result: result.to_string(),
            cached,
        }
    }

    #[test]
    fn counts_and_top_domains() {
        let dns = vec![
            row("a.test", "PASSED", false),
            row("a.test", "BLOCKED", false),
            row("b.test", "CACHED", true),
            row("c.test", "REWRITTEN", false),
        ];
        let summary = summarize(
            &dns,
            &["blocked".to_string(), "passthrough".to_string()],
            None,
        );
        assert_eq!(summary.dns_samples, 4);
        assert_eq!(summary.blocked_dns, 1);
        assert_eq!(summary.rewritten_dns, 1);
        assert_eq!(summary.cached_dns, 1);
        assert_eq!(summary.http_samples, 2);
        assert_eq!(summary.blocked_http, 1);
        assert_eq!(summary.bypassed_http, 1);
        assert_eq!(summary.top_domains[0], ("a.test".to_string(), 2));
        assert!(!summary.is_empty());
        let rendered = summary.render();
        assert!(rendered.starts_with("【近期 DNS 监控统计】\n- 采样数量: 4 条\n"));
        assert!(rendered.contains("- 规则拦截: 1 条, 规则覆写: 1 条, 缓存命中: 1 条"));
        assert!(rendered.contains("  * a.test (请求 2 次)"));
        assert!(rendered.contains("- 采样数量: 2 条, 拦截数: 1, 旁路直连数: 1"));
        assert!(!rendered.ends_with('\n'));
    }

    #[test]
    fn empty_tables_say_so_instead_of_omitting_the_section() {
        let summary = summarize(&[], &[], None);
        assert!(summary.is_empty());
        let rendered = summary.render();
        assert!(rendered.contains("高频请求域名: 采样窗口内没有任何 DNS 记录"));
        assert!(rendered.contains("采样数量: 0 条（未装/未信任 CA 时不产生此类记录）"));
    }

    #[test]
    fn missing_https_surface_is_reported_as_such() {
        let dns = vec![row("a.test", "PASSED", false)];
        let summary = summarize(&dns, &[], Some("极速模式不产生 HTTPS 检查记录".to_string()));
        let rendered = summary.render();
        assert!(rendered.contains("- 本工作模式没有 HTTPS 检查面：极速模式不产生 HTTPS 检查记录"));
        assert!(!rendered.contains("采样数量: 0 条"));
    }

    #[test]
    fn top_domains_are_capped_at_eight_and_ties_break_on_the_domain() {
        let mut dns = Vec::new();
        for index in 0..12 {
            dns.push(row(&format!("h{index}.test"), "PASSED", false));
        }
        dns.push(row("zz.test", "PASSED", false));
        dns.push(row("zz.test", "PASSED", false));
        let summary = summarize(&dns, &[], None);
        assert_eq!(summary.top_domains.len(), 8);
        assert_eq!(summary.top_domains[0], ("zz.test".to_string(), 2));
        let names: Vec<&str> = summary
            .top_domains
            .iter()
            .skip(1)
            .map(|(domain, _)| domain.as_str())
            .collect();
        assert_eq!(
            names,
            ["h0.test", "h1.test", "h10.test", "h11.test", "h2.test", "h3.test", "h4.test"]
        );
    }
}
