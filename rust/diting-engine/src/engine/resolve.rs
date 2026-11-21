use diting_dns_core::message::{TYPE_A, TYPE_AAAA};
use diting_dns_core::reply::REWRITE_ANSWER_TTL;
use diting_dns_wire::format_ipv4;

use super::Engine;

impl Engine {
    pub fn resolve_domain_blocking(&self, domain: &str, ipv4: bool) -> String {
        let domain = domain.to_string();
        if tokio::runtime::Handle::try_current().is_ok() {
            return tokio::task::block_in_place(|| {
                self.runtime
                    .handle()
                    .block_on(async { self.resolve_domain(&domain, ipv4).await })
            });
        }
        self.runtime
            .handle()
            .block_on(async { self.resolve_domain(&domain, ipv4).await })
    }

    pub async fn resolve_domain(&self, domain: &str, ipv4: bool) -> String {
        let domain = diting_config_core::rewrite::normalize_domain(domain);
        if domain.is_empty() {
            return resolve_domain_error_json("empty domain");
        }
        let qtype = if ipv4 { TYPE_A } else { TYPE_AAAA };

        if let Some(entry) = self.rewrites.lookup(&domain) {
            let ip = if ipv4 { entry.ip4 } else { entry.ip6 };
            if !ip.is_empty() {
                return resolve_domain_json(&[ip], &[REWRITE_ANSWER_TTL as i64], "rewrite", "", "");
            }
        }

        if self.filter_dns() && self.policy().is_active() && self.policy().has_rules() {
            if let Some(verdict) = self.policy().evaluate(&domain, "", qtype) {
                if verdict.blocked {
                    return resolve_domain_json(&[], &[], "blocked", &verdict.reason, "");
                }
            }
        }

        let resolver = self.resolver();
        if resolver.is_empty() {
            return resolve_domain_error_json("tunnel resolver not active");
        }

        let response = match resolver.resolve_name(&domain, qtype).await {
            Ok(response) => response,
            Err(error) => return resolve_domain_error_json(&error),
        };
        let Some(extracted) = diting_dns_core::message::extract(&response) else {
            return resolve_domain_error_json("DNS answer extract failed");
        };
        if extracted.blocked {
            return resolve_domain_json(&[], &[], "blocked", "upstream_dns", "");
        }

        let mut ips = Vec::new();
        let mut ttls = Vec::new();
        for record in &extracted.addresses {
            if (record.rrtype == TYPE_A as u8) != ipv4 || record.address.is_empty() {
                continue;
            }
            ips.push(match record.address.len() {
                4 => format_ipv4(&record.address),
                16 => diting_dns_wire::format_ipv6(&record.address),
                _ => continue,
            });
            ttls.push(record.ttl as i64);
        }
        if ips.is_empty() {
            let reason = rcode_text(extracted.rcode);
            return resolve_domain_json(&[], &[], "nodata", &reason, "");
        }
        resolve_domain_json(&ips, &ttls, "upstream", "", "")
    }
}

fn resolve_domain_json(
    ips: &[String],
    ttls: &[i64],
    source: &str,
    reason: &str,
    error: &str,
) -> String {
    let mut document = serde_json::Map::new();
    if !ips.is_empty() {
        document.insert("ips".to_string(), serde_json::json!(ips));
    }
    if !ttls.is_empty() {
        document.insert("ttls".to_string(), serde_json::json!(ttls));
    }
    document.insert("source".to_string(), serde_json::json!(source));
    if !reason.is_empty() {
        document.insert("reason".to_string(), serde_json::json!(reason));
    }
    if !error.is_empty() {
        document.insert("error".to_string(), serde_json::json!(error));
    }
    serde_json::Value::Object(document).to_string()
}

pub fn resolve_domain_error_json(message: &str) -> String {
    let mut document = serde_json::Map::new();
    document.insert("source".to_string(), serde_json::json!(""));
    document.insert("error".to_string(), serde_json::json!(message));
    serde_json::Value::Object(document).to_string()
}

fn rcode_text(rcode: u16) -> String {
    match rcode {
        0 => "NOERROR".to_string(),
        1 => "FORMERR".to_string(),
        2 => "SERVFAIL".to_string(),
        3 => "NXDOMAIN".to_string(),
        4 => "NOTIMP".to_string(),
        5 => "REFUSED".to_string(),
        _ => "no answer records".to_string(),
    }
}
