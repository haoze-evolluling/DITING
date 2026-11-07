//! The binary layouts shared with `desktop/service/internal/core/ratelimit_native.go`.
//!
//! Little endian, a layout byte first, so a stale Go/Rust pair is a loud rejection instead of a
//! misread field.
//!
//! ```text
//! config: u8 layout | u8 enabled | u64 rate_bits | i64 burst | i64 ipv4_prefix | i64 ipv6_prefix
//!         | u32 count | (u32 len | utf8) * count
//! info:   u8 layout | u8 enabled | u32 buckets | u32 exempt_ips | u32 exempt_nets
//!         | u64 rate_bits | i64 burst | u8 ipv4_prefix | u8 ipv6_prefix
//! ```
//!
//! `rate_bits` is `f64::to_bits`, so a NaN or a negative value survives the trip exactly as Go
//! handed it over; normalisation happens in [`crate::limiter`], not in the encoder.
//! Exemption strings are sent raw: trimming, CIDR parsing and `ParseIP` acceptance are the
//! kernel's business, and the Go side must not grow a second opinion about them.

use crate::limiter::{Config, Info, Normalized};

/// Layout version of every payload below; `rateLimitPayloadLayoutVersion` in Go must match.
pub const LAYOUT_VERSION: u8 = 1;

/// Encodes the configuration. Only tests and the Go side (which builds the same bytes) need this.
pub fn encode_config(config: &Config) -> Vec<u8> {
    let mut out = Vec::with_capacity(5 + 8 + 12 + config.exempt.len() * 6);
    out.push(LAYOUT_VERSION);
    out.push(u8::from(config.enabled));
    out.extend_from_slice(&config.rate.to_bits().to_le_bytes());
    out.extend_from_slice(&config.burst.to_le_bytes());
    out.extend_from_slice(&config.ipv4_prefix.to_le_bytes());
    out.extend_from_slice(&config.ipv6_prefix.to_le_bytes());
    push_u32(&mut out, config.exempt.len() as u32);
    for entry in &config.exempt {
        push_text(&mut out, entry);
    }
    out
}

/// Decodes [`encode_config`]: this is how `diting_ratelimit_new`/`configure` read their argument.
pub fn decode_config(data: &[u8]) -> Result<Config, String> {
    let mut reader = Reader::new(data);
    reader.layout("config")?;
    let enabled = reader.u8("enabled")? != 0;
    let rate = f64::from_bits(reader.u64("rate")?);
    let burst = reader.i64("burst")?;
    let ipv4_prefix = reader.i64("ipv4 prefix")?;
    let ipv6_prefix = reader.i64("ipv6 prefix")?;
    let count = reader.u32("exemption count")? as usize;
    let mut exempt = Vec::with_capacity(count.min(1024));
    for _ in 0..count {
        exempt.push(reader.text()?);
    }
    reader.expect_end()?;
    Ok(Config {
        enabled,
        rate,
        burst,
        ipv4_prefix,
        ipv6_prefix,
        exempt,
    })
}

/// Encodes the normalised config and the table sizes for `diting_ratelimit_info`.
pub fn encode_info(info: &Info) -> Vec<u8> {
    let mut out = Vec::with_capacity(35);
    out.push(LAYOUT_VERSION);
    out.push(u8::from(info.config.enabled));
    push_u32(&mut out, info.buckets);
    push_u32(&mut out, info.exempt_ips);
    push_u32(&mut out, info.exempt_nets);
    out.extend_from_slice(&info.config.rate.to_bits().to_le_bytes());
    out.extend_from_slice(&info.config.burst.to_le_bytes());
    out.push(info.config.ipv4_prefix);
    out.push(info.config.ipv6_prefix);
    out
}

/// Decodes [`encode_info`]. The limiter tests and the Go diagnostics use this.
pub fn decode_info(data: &[u8]) -> Result<Info, String> {
    let mut reader = Reader::new(data);
    reader.layout("info")?;
    let enabled = reader.u8("enabled")? != 0;
    let buckets = reader.u32("buckets")?;
    let exempt_ips = reader.u32("exempt ips")?;
    let exempt_nets = reader.u32("exempt nets")?;
    let rate = f64::from_bits(reader.u64("rate")?);
    let burst = reader.i64("burst")?;
    let ipv4_prefix = reader.u8("ipv4 prefix")?;
    let ipv6_prefix = reader.u8("ipv6 prefix")?;
    reader.expect_end()?;
    Ok(Info {
        config: Normalized {
            enabled,
            rate,
            burst,
            ipv4_prefix,
            ipv6_prefix,
        },
        buckets,
        exempt_ips,
        exempt_nets,
    })
}

fn push_u32(out: &mut Vec<u8>, value: u32) {
    out.extend_from_slice(&value.to_le_bytes());
}

fn push_text(out: &mut Vec<u8>, text: &str) {
    push_u32(out, text.len() as u32);
    out.extend_from_slice(text.as_bytes());
}

pub(crate) struct Reader<'a> {
    data: &'a [u8],
    pos: usize,
}

impl<'a> Reader<'a> {
    pub(crate) fn new(data: &'a [u8]) -> Self {
        Reader { data, pos: 0 }
    }

    pub(crate) fn remaining(&self) -> usize {
        self.data.len() - self.pos
    }

    pub(crate) fn u8(&mut self, what: &str) -> Result<u8, String> {
        if self.remaining() < 1 {
            return Err(format!("payload is truncated ({what})"));
        }
        let value = self.data[self.pos];
        self.pos += 1;
        Ok(value)
    }

    pub(crate) fn layout(&mut self, what: &str) -> Result<u8, String> {
        let layout = self.u8(what)?;
        if layout != LAYOUT_VERSION {
            return Err(format!("{what} layout {layout}, expected {LAYOUT_VERSION}"));
        }
        Ok(layout)
    }

    pub(crate) fn u32(&mut self, what: &str) -> Result<u32, String> {
        let bytes = self.fixed::<4>(what)?;
        Ok(u32::from_le_bytes(bytes))
    }

    pub(crate) fn i64(&mut self, what: &str) -> Result<i64, String> {
        let bytes = self.fixed::<8>(what)?;
        Ok(i64::from_le_bytes(bytes))
    }

    pub(crate) fn u64(&mut self, what: &str) -> Result<u64, String> {
        let bytes = self.fixed::<8>(what)?;
        Ok(u64::from_le_bytes(bytes))
    }

    pub(crate) fn text(&mut self) -> Result<String, String> {
        let length = self.u32("text length")? as usize;
        if self.remaining() < length {
            return Err("payload is truncated (text)".to_string());
        }
        let text = std::str::from_utf8(&self.data[self.pos..self.pos + length])
            .map_err(|error| format!("payload text is not UTF-8: {error}"))?;
        self.pos += length;
        Ok(text.to_string())
    }

    pub(crate) fn expect_end(&self) -> Result<(), String> {
        if self.remaining() != 0 {
            return Err(format!("payload has {} trailing bytes", self.remaining()));
        }
        Ok(())
    }

    fn fixed<const N: usize>(&mut self, what: &str) -> Result<[u8; N], String> {
        if self.remaining() < N {
            return Err(format!("payload is truncated ({what})"));
        }
        let mut bytes = [0u8; N];
        bytes.copy_from_slice(&self.data[self.pos..self.pos + N]);
        self.pos += N;
        Ok(bytes)
    }
}

#[cfg(test)]
mod tests;
