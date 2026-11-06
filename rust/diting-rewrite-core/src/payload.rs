//! The binary layout the record entry points share with Go
//! (`desktop/service/internal/core/rewrite_native.go`).
//!
//! Everything is little endian and every payload starts with a layout byte, so a mismatched
//! Go/Rust pair is a loud rejection instead of a misread field. Strings are `u32`-length prefixed:
//! the record path runs once per rule build and once per matched query, and an SVCB value can be
//! longer than the `u16` the matcher payload uses.
//!
//! ```text
//! request:  u8 layout | u16 qtype | u32 ttl | text name | text type | text value
//! reply:    u8 layout | u8 has_record
//!           has_record: u16 rrtype | text owner | u32 ttl | body
//! types:    u8 layout | u16 count | count × text name
//! rejection: the message as UTF-8, without a layout byte (same shape the other kernels use)
//! ```
//!
//! Body of a record, by type (`A` 1, `NS` 2, `CNAME` 5, `PTR` 12, `MX` 15, `TXT` 16, `AAAA` 28,
//! `SRV` 33, `SVCB` 64, `HTTPS` 65):
//!
//! ```text
//! A      | 4 bytes                     AAAA  | 16 bytes
//! CNAME/NS/PTR/TXT | text              MX    | u16 preference | text exchange
//! SRV    | u16 priority | u16 weight | u16 port | text target
//! SVCB/HTTPS | u16 priority | text target | u16 param count | params
//! ```
//!
//! Parameters are `u16 key` followed by their data: `mandatory` u16 count + u16 keys, `alpn` u16
//! count + texts, `no-default-alpn` nothing, `port` u16, `ipv4hint` u16 count + 4-byte addresses,
//! `ech` u32 length + bytes, `ipv6hint` u16 count + 16-byte addresses, `dohpath` text.

use std::fmt;

use crate::record::{ParsedRecord, Record, SvcParam};

/// Layout version of every payload below; `rewritePayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

/// Why a request could not be decoded; the message is surfaced to the Go caller.
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

/// One record build request.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Request {
    /// The query name the record is attached to; Go passes it as the query spelled it.
    pub owner: String,
    /// The query type the record has to answer.
    pub qtype: u16,
    /// TTL the caller wants on the record.
    pub ttl: u32,
    /// Configured type name (`MX`, `HTTPS`, ...).
    pub type_name: String,
    /// Configured value text.
    pub value: String,
}

/// Decodes a build request.
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

/// Encodes the reply: either "no record for this query type" or one typed record.
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

/// Encodes the reply of the type-list entry point.
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
        Record::Cname(name) | Record::Ns(name) | Record::Ptr(name) | Record::Txt(name) => {
            push_text(out, name)
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
