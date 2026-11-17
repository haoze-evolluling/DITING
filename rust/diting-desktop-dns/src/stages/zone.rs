//! Locally authoritative zones.
//!
//! Unlike hosts/rewrite, a zone owns every name below its origin: a name inside the zone that has
//! no matching record is an authoritative NODATA with the zone SOA, not a reason to ask upstream.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_core::zone::{ZoneEngine, ZoneRData, ZoneRecord};
use diting_dns_wire::build::{RData, ResourceRecord};
use diting_dns_wire::CLASS_IN;

use crate::context::DnsContext;
use crate::pipeline::{Stage, StageResult};
use crate::stages::util::{respond, start_reply};

pub struct ZoneStage {
    engine: Arc<ZoneEngine>,
}

impl ZoneStage {
    pub fn new(engine: Arc<ZoneEngine>) -> Self {
        Self { engine }
    }
}

#[async_trait]
impl Stage for ZoneStage {
    fn name(&self) -> &'static str {
        "zone"
    }

    async fn before(&self, ctx: &mut DnsContext) -> StageResult {
        if !self.engine.enabled() {
            return StageResult::Continue;
        }
        let answer = self.engine.lookup(&ctx.question.name, ctx.question.qtype);
        if !answer.matched {
            return StageResult::Continue;
        }
        let Some(mut builder) = start_reply(ctx) else {
            return StageResult::Fail("空查询报文".to_string());
        };
        builder = builder.set_rcode(answer.rcode.min(255) as u8);
        for record in &answer.answers {
            builder = builder.push_answer(to_wire(record));
        }
        for record in &answer.authority {
            builder = builder.push_authority(to_wire(record));
        }
        let nodata = answer.answers.is_empty();
        respond(ctx, builder);
        ctx.set("source", "zone");
        ctx.set("cache_hit", if nodata { "zone_nodata" } else { "zone" });
        StageResult::Stop
    }
}

fn to_wire(record: &ZoneRecord) -> ResourceRecord {
    let rdata = match &record.rdata {
        ZoneRData::A(ip) => RData::A(*ip),
        ZoneRData::Aaaa(ip) => RData::Aaaa(*ip),
        ZoneRData::Cname(name) => RData::Cname(name.clone()),
        ZoneRData::Ptr(name) => RData::Ptr(name.clone()),
        ZoneRData::Ns(name) => RData::Ns(name.clone()),
        ZoneRData::Mx {
            preference,
            exchange,
        } => RData::Mx {
            preference: *preference,
            exchange: exchange.clone(),
        },
        ZoneRData::Txt(values) => RData::Txt(
            values
                .iter()
                .map(|value| value.as_bytes().to_vec())
                .collect(),
        ),
        ZoneRData::Srv {
            priority,
            weight,
            port,
            target,
        } => RData::Srv {
            priority: *priority,
            weight: *weight,
            port: *port,
            target: target.clone(),
        },
        ZoneRData::Soa {
            mname,
            rname,
            serial,
            refresh,
            retry,
            expire,
            minimum,
        } => RData::Soa {
            mname: mname.clone(),
            rname: rname.clone(),
            serial: *serial,
            refresh: *refresh,
            retry: *retry,
            expire: *expire,
            minimum: *minimum,
        },
        ZoneRData::Caa { flags, tag, value } => RData::Caa {
            flags: *flags,
            tag: tag.clone(),
            value: value.as_bytes().to_vec(),
        },
    };
    ResourceRecord::new(
        record.owner.clone(),
        record.rtype,
        CLASS_IN,
        record.ttl,
        rdata,
    )
}
