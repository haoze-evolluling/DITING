use async_trait::async_trait;
use diting_dns_wire::build::{
    MessageBuilder, OptBuilder, RData, ResourceRecord, SvcParam, SvcbRData,
};
use diting_dns_wire::{CLASS_IN, TYPE_SVCB};

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{normalize_trailing_dot, normalized_name, respond};
use crate::stages::ConfigHandle;

pub const DDR_QUERY_NAME: &str = "_dns.resolver.arpa.";
const DDR_PRIORITY: u16 = 1;
const DDR_TTL: u32 = 600;

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct DdrAnswer {
    pub server_name: String,
    pub dot_enabled: bool,
    pub doh_enabled: bool,
    pub doq_enabled: bool,
    pub dot_port: u16,
    pub doh_port: u16,
    pub doq_port: u16,
    pub doh_path: String,
    pub cert_has_ips: bool,
}

impl DdrAnswer {
    pub fn is_empty(&self) -> bool {
        !self.dot_enabled && !self.doh_enabled && !self.doq_enabled
    }
}

pub trait DdrProvider: Send + Sync {
    fn answer(&self) -> DdrAnswer;
}

pub struct DdrStage {
    config: ConfigHandle,
    provider: std::sync::Arc<dyn DdrProvider>,
}

impl DdrStage {
    pub fn new(config: ConfigHandle, provider: std::sync::Arc<dyn DdrProvider>) -> Self {
        Self { config, provider }
    }
}

#[async_trait]
impl Stage for DdrStage {
    fn name(&self) -> &'static str {
        "ddr"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let (enabled, ddr_enabled) = {
            let config = self
                .config
                .read()
                .unwrap_or_else(|error| error.into_inner());
            (config.encrypted.enabled, config.encrypted.ddr_enabled)
        };
        if !enabled || !ddr_enabled {
            return StageResult::Continue;
        }
        if normalized_name(&ctx.question.name) != normalized_name(DDR_QUERY_NAME) {
            return StageResult::Continue;
        }
        let answer = self.provider.answer();
        if answer.is_empty() {
            return StageResult::Continue;
        }
        let Some(mut builder) = MessageBuilder::reply_to(&ctx.request) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        builder = builder
            .set_authoritative(true)
            .set_recursion_available(true);
        if let Some(opt) = diting_dns_wire::build::parse_opt(&ctx.request) {
            let mut response_opt = OptBuilder::new(opt.udp_size);
            if opt.do_bit {
                response_opt = response_opt.with_do_bit(true);
            }
            builder = builder.with_opt(response_opt);
        }
        if ctx.question.qtype == TYPE_SVCB {
            let target = normalize_trailing_dot(answer.server_name.trim());
            if target != "." {
                if answer.doh_enabled {
                    builder = builder.push_answer(svcb_record(
                        &target,
                        vec![
                            SvcParam::alpn(&["h2"]),
                            SvcParam::port(answer.doh_port),
                            SvcParam::dohpath(&doh_path_template(&answer.doh_path)),
                        ],
                    ));
                }
                if answer.dot_enabled && answer.cert_has_ips {
                    builder = builder.push_answer(svcb_record(
                        &target,
                        vec![SvcParam::alpn(&["dot"]), SvcParam::port(answer.dot_port)],
                    ));
                }
                if answer.doq_enabled {
                    builder = builder.push_answer(svcb_record(
                        &target,
                        vec![SvcParam::alpn(&["doq"]), SvcParam::port(answer.doq_port)],
                    ));
                }
            }
        }
        respond(ctx, builder);
        ctx.set("ddr_handled", "true");
        ctx.set("source", "ddr");
        StageResult::Stop
    }
}

fn svcb_record(target: &str, params: Vec<SvcParam>) -> ResourceRecord {
    ResourceRecord::new(
        DDR_QUERY_NAME,
        TYPE_SVCB,
        CLASS_IN,
        DDR_TTL,
        RData::Svcb(SvcbRData {
            priority: DDR_PRIORITY,
            target: target.to_string(),
            params,
        }),
    )
}

pub fn doh_path_template(path: &str) -> String {
    let path = normalize_doh_path(path);
    if path.contains("{?dns}") {
        path
    } else {
        format!("{path}{{?dns}}")
    }
}

pub fn normalize_doh_path(path: &str) -> String {
    let trimmed = path.trim();
    if trimmed.is_empty() {
        "/dns-query".to_string()
    } else if trimmed.starts_with('/') {
        trimmed.to_string()
    } else {
        format!("/{trimmed}")
    }
}

pub fn cert_has_ips(ips: &[String]) -> bool {
    ips.iter()
        .any(|ip| ip.trim().parse::<std::net::IpAddr>().is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_answer_advertises_nothing() {
        assert!(DdrAnswer::default().is_empty());
    }

    #[test]
    fn doh_path_gets_the_placeholder() {
        assert_eq!(doh_path_template("/dns-query"), "/dns-query{?dns}");
        assert_eq!(doh_path_template("/dns-query{?dns}"), "/dns-query{?dns}");
    }

    #[test]
    fn ip_sans_are_detected() {
        assert!(cert_has_ips(&["127.0.0.1".into(), "example.com".into()]));
        assert!(!cert_has_ips(&["example.com".into()]));
    }
}
