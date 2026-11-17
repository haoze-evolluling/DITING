//! EDNS Client Subnet privacy and spoofing (RFC 7871).
//!
//! Two modes: strip the client's real subnet (privacy) or replace it with a configured subnet
//! (geo-unlocking while hiding the client). The mutation happens on the outgoing query, after the
//! cache key was already computed from the question, so grouping and caching stay stable.

use std::net::IpAddr;

use async_trait::async_trait;
use diting_dns_wire::build::{EcsOption, EdnsOption, ParsedMessage, OPTION_ECS};

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::ConfigHandle;

pub struct EcsStage {
    config: ConfigHandle,
}

impl EcsStage {
    pub fn new(config: ConfigHandle) -> Self {
        Self { config }
    }
}

#[async_trait]
impl Stage for EcsStage {
    fn name(&self) -> &'static str {
        "ecs"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        let (enabled, strip, custom) = {
            let config = self
                .config
                .read()
                .unwrap_or_else(|error| error.into_inner());
            (
                config.ecs.enabled,
                config.ecs.strip_ecs,
                config.ecs.custom_subnet.clone(),
            )
        };
        if !enabled {
            return StageResult::Continue;
        }
        let Some(mut message) = ParsedMessage::parse(&ctx.request) else {
            return StageResult::Continue;
        };
        let mut changed = false;
        if !custom.trim().is_empty() {
            changed |= message.remove_opt_option(OPTION_ECS);
            match parse_subnet(custom.trim()) {
                Ok((ip, prefix)) => {
                    message.push_opt_option(EdnsOption::Ecs(EcsOption::from_ip(ip, prefix, 0)));
                    ctx.set("ecs_injected", custom.trim());
                    changed = true;
                }
                Err(error) => {
                    ctx.set("ecs_error", error);
                }
            }
        } else if strip {
            changed = message.remove_opt_option(OPTION_ECS);
            if changed {
                ctx.set("ecs_stripped", "true");
            }
        }
        if changed {
            if let Some(wire) = message.to_wire() {
                ctx.request = wire;
            }
        }
        StageResult::Continue
    }
}

/// Parses `1.2.3.0/24` or `2001:db8::/32`. A bare address is treated as a full-length prefix.
pub fn parse_subnet(text: &str) -> Result<(IpAddr, u8), String> {
    let (address, prefix) = match text.split_once('/') {
        Some((address, prefix)) => (address, Some(prefix)),
        None => (text, None),
    };
    let ip: IpAddr = address
        .trim()
        .parse()
        .map_err(|_| format!("无效的 ECS 子网地址: {text}"))?;
    let max = if ip.is_ipv4() { 32 } else { 128 };
    let prefix = match prefix {
        Some(value) => value
            .trim()
            .parse::<u8>()
            .map_err(|_| format!("无效的 ECS 前缀长度: {text}"))?,
        None => max,
    };
    if prefix > max {
        return Err(format!("ECS 前缀长度超出范围: {text}"));
    }
    Ok((ip, prefix))
}

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::{MessageBuilder, OptBuilder};
    use diting_dns_wire::CLASS_IN;

    fn context(opt: bool) -> DnsContext {
        let builder = MessageBuilder::query("example.com", 1, CLASS_IN);
        let query = if opt {
            builder.with_opt(OptBuilder::new(1232)).finish().unwrap()
        } else {
            builder.finish().unwrap()
        };
        DnsContext::new(query, None, crate::context::Transport::Udp).unwrap()
    }

    #[tokio::test]
    async fn custom_subnet_replaces_client_ecs() {
        let config = std::sync::Arc::new(std::sync::RwLock::new(
            diting_desktop_api::config::Config::default(),
        ));
        config.write().unwrap().ecs.custom_subnet = "203.0.113.0/24".to_string();
        let stage = EcsStage::new(config);
        let mut ctx = context(true);
        stage.before(&mut ctx).await;
        let message = ParsedMessage::parse(&ctx.request).unwrap();
        let ecs = message
            .opt_options()
            .iter()
            .find_map(|option| match option {
                EdnsOption::Ecs(ecs) => Some(ecs),
                _ => None,
            })
            .unwrap();
        assert_eq!(ecs.family, 1);
        assert_eq!(ecs.source_prefix, 24);
        assert_eq!(&ecs.address[..3], &[203, 0, 113]);
    }

    #[test]
    fn subnet_parser_bounds_prefixes() {
        assert_eq!(parse_subnet("192.0.2.0/24").unwrap().1, 24);
        assert_eq!(parse_subnet("2001:db8::/32").unwrap().1, 32);
        assert!(parse_subnet("192.0.2.0/33").is_err());
        assert!(parse_subnet("nope").is_err());
    }
}
