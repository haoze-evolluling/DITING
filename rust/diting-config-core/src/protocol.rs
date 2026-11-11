//! The two name tables: the upstream protocol (`ParseProtocol`) and the block response mode
//! (`ParseResponseType`).
//!
//! Both are "unknown spelling means the zero value" tables, and both zero values are the defaults
//! (`PLAIN` upstreams, `CUSTOM_IP` blocks). The protocol table folds case (`strings.ToUpper`), the
//! response table does not: `ApplyDNSConfig` upper-cases the config value itself before calling it,
//! while `SetBlockResponseType` passes the caller's text straight in — so `"nxdomain"` from a
//! settings payload is `CUSTOM_IP`, exactly as before.

use diting_go_compat::text::go_upper;

use crate::quote::go_quote;

/// `DNSProtocol`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Protocol {
    Plain,
    Doh,
    Dot,
    Doq,
}

impl Protocol {
    pub fn code(self) -> i64 {
        match self {
            Protocol::Plain => 0,
            Protocol::Doh => 1,
            Protocol::Dot => 2,
            Protocol::Doq => 3,
        }
    }

    pub fn from_code(code: i64) -> Option<Self> {
        match code {
            0 => Some(Protocol::Plain),
            1 => Some(Protocol::Doh),
            2 => Some(Protocol::Dot),
            3 => Some(Protocol::Doq),
            _ => None,
        }
    }

    /// The name `dnsProviderConfig.Protocol` holds after normalization (`PLAIN`, `DOH`, `DOT`, `DOQ`).
    pub fn name(self) -> &'static str {
        match self {
            Protocol::Plain => "PLAIN",
            Protocol::Doh => "DOH",
            Protocol::Dot => "DOT",
            Protocol::Doq => "DOQ",
        }
    }
}

/// `ParseProtocol`: upper-case, then match; anything unknown is `PLAIN`.
pub fn parse_protocol(text: &str) -> Protocol {
    let upper = go_upper(text);
    match upper.as_ref() {
        "DOH" => Protocol::Doh,
        "DOT" => Protocol::Dot,
        "DOQ" => Protocol::Doq,
        _ => Protocol::Plain,
    }
}

/// The validated protocol of one provider: `strings.ToUpper` then the strict table, which rejects
/// anything that is not one of the four (`unsupported protocol "HYPER"`). The error carries the
/// upper-cased spelling, because the old caller upper-cased before validating.
pub fn validated_protocol(text: &str) -> Result<Protocol, String> {
    let upper = go_upper(text);
    match upper.as_ref() {
        "PLAIN" => Ok(Protocol::Plain),
        "DOH" => Ok(Protocol::Doh),
        "DOT" => Ok(Protocol::Dot),
        "DOQ" => Ok(Protocol::Doq),
        // `ApplyDNSConfig` upper-cased the name before validating, so the error shows that form.
        _ => Err(format!("unsupported protocol {}", go_quote(&upper))),
    }
}

/// `ResponseType`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResponseType {
    CustomIp,
    NxDomain,
    Refused,
    NoData,
}

impl ResponseType {
    pub fn code(self) -> i64 {
        match self {
            ResponseType::CustomIp => 0,
            ResponseType::NxDomain => 1,
            ResponseType::Refused => 2,
            ResponseType::NoData => 3,
        }
    }

    pub fn from_code(code: i64) -> Option<Self> {
        match code {
            0 => Some(ResponseType::CustomIp),
            1 => Some(ResponseType::NxDomain),
            2 => Some(ResponseType::Refused),
            3 => Some(ResponseType::NoData),
            _ => None,
        }
    }
}

/// `ParseResponseType`: case-sensitive, unknown means `CUSTOM_IP`.
pub fn parse_response_type(text: &str) -> ResponseType {
    match text {
        "NXDOMAIN" => ResponseType::NxDomain,
        "REFUSED" => ResponseType::Refused,
        "NODATA" => ResponseType::NoData,
        _ => ResponseType::CustomIp,
    }
}

/// `ParseResponseType(strings.ToUpper(text))`, the shape `ApplyDNSConfig` used.
pub fn parse_response_type_upper(text: &str) -> ResponseType {
    parse_response_type(&go_upper(text))
}

#[cfg(test)]
mod tests;
