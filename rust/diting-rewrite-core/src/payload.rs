use std::fmt;

use crate::action::Action;
use crate::engine::{Config, LookupResult, RecordSpec, RuleConfig};
use crate::record::{ParsedRecord, Record, SvcParam};

pub const LAYOUT_VERSION: u8 = 1;

#[derive(Debug)]
pub struct DecodeError(pub String);

impl fmt::Display for DecodeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl DecodeError {
    fn truncated(field: &str) -> Self {
        Self(format!("record payload is truncated ({field})"))
    }

    pub(crate) fn invalid(message: impl Into<String>) -> Self {
        Self(message.into())
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    pub owner: String,
    pub qtype: u16,
    pub ttl: u32,
    pub type_name: String,
    pub value: String,
}

pub fn decode_request(data: &[u8]) -> Result<Request, DecodeError> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(DecodeError::invalid(format!(
            "record request layout {layout}, expected {LAYOUT_VERSION}"
        )));
    }
    let qtype = reader.u16("qtype")?;
    let ttl = reader.u32("ttl")?;
    let owner = reader.text("name")?;
    let type_name = reader.text("type")?;
    let value = reader.text("value")?;
    reader.expect_end()?;
    Ok(Request {
        owner,
        qtype,
        ttl,
        type_name,
        value,
    })
}

pub fn encode_reply(record: Option<&ParsedRecord>) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    let Some(record) = record else {
        out.push(0);
        return out;
    };
    out.push(1);
    out.extend_from_slice(&record.record.rrtype().to_le_bytes());
    push_text(&mut out, &record.owner);
    out.extend_from_slice(&record.ttl.to_le_bytes());
    encode_body(&mut out, &record.record);
    out
}

pub fn decode_action_text(data: &[u8]) -> Result<String, DecodeError> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(DecodeError::invalid(format!(
            "action request layout {layout}, expected {LAYOUT_VERSION}"
        )));
    }
    let value = reader.text("value")?;
    reader.expect_end()?;
    Ok(value)
}

pub fn decode_action(data: &[u8]) -> Result<Action, DecodeError> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(DecodeError::invalid(format!(
            "action request layout {layout}, expected {LAYOUT_VERSION}"
        )));
    }
    let bare = match reader.u8("bare")? {
        0 => false,
        1 => true,
        other => {
            return Err(DecodeError::invalid(format!(
                "action payload has unknown bare flag {other}"
            )))
        }
    };
    let rcode = reader.u16("rcode")?;
    let rrtype = reader.u16("rrtype")?;
    let value = reader.text("value")?;
    reader.expect_end()?;
    Ok(Action {
        bare,
        rcode,
        rrtype,
        value,
    })
}

pub fn encode_action(action: &Action) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION, u8::from(action.bare)];
    out.extend_from_slice(&action.rcode.to_le_bytes());
    out.extend_from_slice(&action.rrtype.to_le_bytes());
    push_text(&mut out, &action.value);
    out
}

pub fn encode_action_key(key: &str) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    push_text(&mut out, key);
    out
}

pub fn encode_type_names(names: &[&str]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&(names.len() as u16).to_le_bytes());
    for name in names {
        push_text(&mut out, name);
    }
    out
}

fn encode_body(out: &mut Vec<u8>, record: &Record) {
    match record {
        Record::A(address) => out.extend_from_slice(address),
        Record::Aaaa(address) => out.extend_from_slice(address),
        Record::Cname(name) | Record::Ns(name) | Record::Ptr(name) => push_text(out, name),
        Record::Txt(texts) => {
            out.extend_from_slice(&(texts.len() as u32).to_le_bytes());
            for text in texts {
                push_text(out, text);
            }
        }
        Record::Mx {
            preference,
            exchange,
        } => {
            out.extend_from_slice(&preference.to_le_bytes());
            push_text(out, exchange);
        }
        Record::Srv {
            priority,
            weight,
            port,
            target,
        } => {
            out.extend_from_slice(&priority.to_le_bytes());
            out.extend_from_slice(&weight.to_le_bytes());
            out.extend_from_slice(&port.to_le_bytes());
            push_text(out, target);
        }
        Record::Svcb {
            priority,
            target,
            params,
            ..
        } => {
            out.extend_from_slice(&priority.to_le_bytes());
            push_text(out, target);
            out.extend_from_slice(&(params.len() as u16).to_le_bytes());
            for param in params {
                encode_param(out, param);
            }
        }
    }
}

fn encode_param(out: &mut Vec<u8>, param: &SvcParam) {
    out.extend_from_slice(&param.key().to_le_bytes());
    match param {
        SvcParam::Mandatory(keys) => {
            out.extend_from_slice(&(keys.len() as u16).to_le_bytes());
            for key in keys {
                out.extend_from_slice(&key.to_le_bytes());
            }
        }
        SvcParam::Alpn(values) => {
            out.extend_from_slice(&(values.len() as u16).to_le_bytes());
            for value in values {
                push_text(out, value);
            }
        }
        SvcParam::NoDefaultAlpn => {}
        SvcParam::Port(port) => out.extend_from_slice(&port.to_le_bytes()),
        SvcParam::Ipv4Hint(addresses) => {
            out.extend_from_slice(&(addresses.len() as u16).to_le_bytes());
            for address in addresses {
                out.extend_from_slice(address);
            }
        }
        SvcParam::Ech(raw) => {
            out.extend_from_slice(&(raw.len() as u32).to_le_bytes());
            out.extend_from_slice(raw);
        }
        SvcParam::Ipv6Hint(addresses) => {
            out.extend_from_slice(&(addresses.len() as u16).to_le_bytes());
            for address in addresses {
                out.extend_from_slice(address);
            }
        }
        SvcParam::DoHPath(template) => push_text(out, template),
    }
}

fn push_text(out: &mut Vec<u8>, value: &str) {
    out.extend_from_slice(&(value.len() as u32).to_le_bytes());
    out.extend_from_slice(value.as_bytes());
}

pub fn decode_engine_config(data: &[u8]) -> Result<Config, DecodeError> {
    let mut reader = Reader::new(data);
    let layout = reader.u8("layout")?;
    if layout != LAYOUT_VERSION {
        return Err(DecodeError::invalid(format!(
            "engine request layout {layout}, expected {LAYOUT_VERSION}"
        )));
    }
    let enabled = reader.u8("enabled")? != 0;
    let default_ttl = reader.u32("default ttl")?;
    let rule_count = reader.u32("rule count")?;
    let mut rules = Vec::new();
    for _ in 0..rule_count {
        rules.push(decode_engine_rule(&mut reader)?);
    }
    reader.expect_end()?;
    Ok(Config {
        enabled,
        default_ttl,
        rules,
    })
}

fn decode_engine_rule(reader: &mut Reader<'_>) -> Result<RuleConfig, DecodeError> {
    let domain = reader.text("domain")?;
    let ttl = reader.u32("ttl")?;
    let ip_count = reader.u32("ip count")?;
    let mut ips = Vec::new();
    for _ in 0..ip_count {
        ips.push(reader.text("ip")?);
    }
    let cname = reader.text("cname")?;
    let txt_count = reader.u32("txt count")?;
    let mut txt = Vec::new();
    for _ in 0..txt_count {
        txt.push(reader.text("txt")?);
    }
    let record_count = reader.u32("record count")?;
    let mut records = Vec::new();
    for _ in 0..record_count {
        let type_name = reader.text("record type")?;
        let value = reader.text("record value")?;
        records.push(RecordSpec { type_name, value });
    }
    let rcode = reader.text("rcode")?;
    Ok(RuleConfig {
        domain,
        ips,
        cname,
        txt,
        ttl,
        records,
        rcode,
    })
}

pub fn encode_engine_build(warnings: &[String]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&(warnings.len() as u32).to_le_bytes());
    for warning in warnings {
        push_text(&mut out, warning);
    }
    out
}

pub fn encode_engine_lookup(result: &LookupResult) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.push(u8::from(result.matched));
    out.extend_from_slice(&result.rcode.to_le_bytes());
    out.extend_from_slice(&(result.answers.len() as u32).to_le_bytes());
    for answer in &result.answers {
        out.extend_from_slice(&answer.record.rrtype().to_le_bytes());
        push_text(&mut out, &answer.owner);
        out.extend_from_slice(&answer.ttl.to_le_bytes());
        encode_body(&mut out, &answer.record);
    }
    out
}

pub fn encode_engine_domains(domains: &[String]) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    out.extend_from_slice(&(domains.len() as u32).to_le_bytes());
    for domain in domains {
        push_text(&mut out, domain);
    }
    out
}

pub fn encode_engine_reverse(domain: Option<&str>) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    match domain {
        Some(domain) => {
            out.push(1);
            push_text(&mut out, domain);
        }
        None => out.push(0),
    }
    out
}

struct Reader<'a> {
    data: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(data: &'a [u8]) -> Self {
        Self { data, position: 0 }
    }

    fn remaining(&self) -> usize {
        self.data.len() - self.position
    }

    fn u8(&mut self, field: &str) -> Result<u8, DecodeError> {
        if self.remaining() < 1 {
            return Err(DecodeError::truncated(field));
        }
        let value = self.data[self.position];
        self.position += 1;
        Ok(value)
    }

    fn u16(&mut self, field: &str) -> Result<u16, DecodeError> {
        if self.remaining() < 2 {
            return Err(DecodeError::truncated(field));
        }
        let value = u16::from_le_bytes([self.data[self.position], self.data[self.position + 1]]);
        self.position += 2;
        Ok(value)
    }

    fn u32(&mut self, field: &str) -> Result<u32, DecodeError> {
        if self.remaining() < 4 {
            return Err(DecodeError::truncated(field));
        }
        let mut bytes = [0u8; 4];
        bytes.copy_from_slice(&self.data[self.position..self.position + 4]);
        self.position += 4;
        Ok(u32::from_le_bytes(bytes))
    }

    fn text(&mut self, field: &str) -> Result<String, DecodeError> {
        let length = self.u32(field)? as usize;
        if self.remaining() < length {
            return Err(DecodeError::truncated(field));
        }
        let slice = &self.data[self.position..self.position + length];
        self.position += length;
        String::from_utf8(slice.to_vec())
            .map_err(|_| DecodeError::invalid(format!("{field} is not valid UTF-8")))
    }

    fn expect_end(&self) -> Result<(), DecodeError> {
        if self.remaining() == 0 {
            Ok(())
        } else {
            Err(DecodeError::invalid(format!(
                "record payload has {} trailing bytes",
                self.remaining()
            )))
        }
    }
}
