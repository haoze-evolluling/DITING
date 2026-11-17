//! Record payload decoding: the inverse of [`super::rdata::RData::encode`].
//!
//! `wire` is always the whole message, because every name inside rdata may legally use a
//! compression pointer whose target is message-relative. `end` caps how far the *inline* bytes of
//! this rdata may reach; pointers are still followed through the full message by
//! [`crate::unpack_name`]. A name that does not consume its rdata exactly is rejected: re-encoding
//! would otherwise silently drop the trailing bytes.

use std::net::{Ipv4Addr, Ipv6Addr};

use crate::bits::{read_u16, read_u32};
use crate::build::rdata::{RData, SvcParam, SvcbRData};
use crate::build::types::{
    TYPE_A, TYPE_AAAA, TYPE_CAA, TYPE_CNAME, TYPE_HINFO, TYPE_HTTPS, TYPE_MX, TYPE_NAPTR, TYPE_NS,
    TYPE_PTR, TYPE_SOA, TYPE_SRV, TYPE_SVCB, TYPE_TXT,
};
use crate::name::unpack_name;

/// Decodes one record payload laid out at `wire[start..start + rdlength]`.
///
/// Returns `None` when the declared length runs past the message or a known record type is
/// malformed. Unknown types (and the empty payload of any non-TXT type) are preserved verbatim as
/// [`RData::Raw`], so a message can be rewritten without losing records.
pub fn parse_rdata(wire: &[u8], start: usize, rdlength: usize, rtype: u16) -> Option<RData> {
    let end = start.checked_add(rdlength)?;
    if end > wire.len() {
        return None;
    }
    let bytes = &wire[start..end];

    if rdlength == 0 {
        // A zero-length TXT is an empty string list; for every other type keep the empty payload
        // as raw bytes so the round trip is exact.
        return Some(if rtype == TYPE_TXT {
            RData::Txt(Vec::new())
        } else {
            RData::Raw(Vec::new())
        });
    }

    Some(match rtype {
        TYPE_A => {
            let octets: [u8; 4] = bytes.try_into().ok()?;
            RData::A(Ipv4Addr::from(octets))
        }
        TYPE_AAAA => {
            let octets: [u8; 16] = bytes.try_into().ok()?;
            RData::Aaaa(Ipv6Addr::from(octets))
        }
        TYPE_CNAME => RData::Cname(name_only(wire, start, end)?),
        TYPE_PTR => RData::Ptr(name_only(wire, start, end)?),
        TYPE_NS => RData::Ns(name_only(wire, start, end)?),
        TYPE_SOA => {
            let (mname, offset) = unpack_name(wire, start, end)?;
            let (rname, offset) = unpack_name(wire, offset, end)?;
            if offset.checked_add(20)? != end {
                return None;
            }
            RData::Soa {
                mname,
                rname,
                serial: read_u32(wire, offset)?,
                refresh: read_u32(wire, offset + 4)?,
                retry: read_u32(wire, offset + 8)?,
                expire: read_u32(wire, offset + 12)?,
                minimum: read_u32(wire, offset + 16)?,
            }
        }
        TYPE_MX => {
            if start.checked_add(2)? > end {
                return None;
            }
            let preference = read_u16(wire, start)?;
            let (exchange, offset) = unpack_name(wire, start + 2, end)?;
            if offset != end {
                return None;
            }
            RData::Mx {
                preference,
                exchange,
            }
        }
        TYPE_TXT => RData::Txt(character_strings(wire, start, end)?),
        TYPE_SRV => {
            if start.checked_add(6)? > end {
                return None;
            }
            let (target, offset) = unpack_name(wire, start + 6, end)?;
            if offset != end {
                return None;
            }
            RData::Srv {
                priority: read_u16(wire, start)?,
                weight: read_u16(wire, start + 2)?,
                port: read_u16(wire, start + 4)?,
                target,
            }
        }
        TYPE_HINFO => {
            let (cpu, offset) = read_character_string(wire, start, end)?;
            let (os, offset) = read_character_string(wire, offset, end)?;
            if offset != end {
                return None;
            }
            RData::Hinfo { cpu, os }
        }
        TYPE_CAA => {
            if bytes.len() < 2 {
                return None;
            }
            let tag_length = usize::from(bytes[1]);
            let tag_end = 2usize.checked_add(tag_length)?;
            if tag_end > bytes.len() {
                return None;
            }
            RData::Caa {
                flags: bytes[0],
                tag: String::from_utf8(bytes[2..tag_end].to_vec()).ok()?,
                value: bytes[tag_end..].to_vec(),
            }
        }
        TYPE_NAPTR => {
            if start.checked_add(4)? > end {
                return None;
            }
            let order = read_u16(wire, start)?;
            let preference = read_u16(wire, start + 2)?;
            let (flags, offset) = read_character_string(wire, start + 4, end)?;
            let (services, offset) = read_character_string(wire, offset, end)?;
            let (regexp, offset) = read_character_string(wire, offset, end)?;
            let (replacement, offset) = unpack_name(wire, offset, end)?;
            if offset != end {
                return None;
            }
            RData::Naptr {
                order,
                preference,
                flags,
                services,
                regexp,
                replacement,
            }
        }
        TYPE_SVCB | TYPE_HTTPS => {
            if start.checked_add(2)? > end {
                return None;
            }
            let priority = read_u16(wire, start)?;
            let (target, offset) = unpack_name(wire, start + 2, end)?;
            let params = decode_svc_params(&wire[offset..end])?;
            let data = SvcbRData {
                priority,
                target,
                params,
            };
            if rtype == TYPE_SVCB {
                RData::Svcb(data)
            } else {
                RData::Https(data)
            }
        }
        _ => RData::Raw(bytes.to_vec()),
    })
}

/// Decodes the `(key, length, value)` triplets of an SVCB/HTTPS parameter list.
///
/// Order is preserved exactly as it appeared on the wire; the encoder re-sorts it later because
/// RFC 9460 requires strictly increasing keys.
pub fn decode_svc_params(bytes: &[u8]) -> Option<Vec<SvcParam>> {
    let mut params = Vec::new();
    let mut offset = 0usize;
    while offset < bytes.len() {
        if offset.checked_add(4)? > bytes.len() {
            return None;
        }
        let key = u16::from_be_bytes([bytes[offset], bytes[offset + 1]]);
        let length = usize::from(u16::from_be_bytes([bytes[offset + 2], bytes[offset + 3]]));
        let start = offset + 4;
        let end = start.checked_add(length)?;
        if end > bytes.len() {
            return None;
        }
        params.push(SvcParam::new(key, bytes[start..end].to_vec()));
        offset = end;
    }
    Some(params)
}

/// Reads a lone name and insists it fills the whole rdata.
fn name_only(wire: &[u8], start: usize, end: usize) -> Option<String> {
    let (name, offset) = unpack_name(wire, start, end)?;
    if offset != end {
        return None;
    }
    Some(name)
}

/// Reads `count`-prefixed `<character-string>`s until `end`.
fn character_strings(wire: &[u8], start: usize, end: usize) -> Option<Vec<Vec<u8>>> {
    let mut strings = Vec::new();
    let mut offset = start;
    while offset < end {
        let length = usize::from(wire[offset]);
        let data_start = offset.checked_add(1)?;
        let data_end = data_start.checked_add(length)?;
        if data_end > end {
            return None;
        }
        strings.push(wire[data_start..data_end].to_vec());
        offset = data_end;
    }
    Some(strings)
}

/// Reads one UTF-8 `<character-string>` and returns it with the offset just past it.
fn read_character_string(wire: &[u8], start: usize, end: usize) -> Option<(String, usize)> {
    if start >= end {
        return None;
    }
    let length = usize::from(wire[start]);
    let data_start = start + 1;
    let data_end = data_start.checked_add(length)?;
    if data_end > end {
        return None;
    }
    let text = String::from_utf8(wire[data_start..data_end].to_vec()).ok()?;
    Some((text, data_end))
}
