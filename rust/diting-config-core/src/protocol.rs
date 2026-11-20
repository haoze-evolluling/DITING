use diting_go_compat::text::go_upper;

use crate::quote::go_quote;

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

    pub fn name(self) -> &'static str {
        match self {
            Protocol::Plain => "PLAIN",
            Protocol::Doh => "DOH",
            Protocol::Dot => "DOT",
            Protocol::Doq => "DOQ",
        }
    }
}

pub fn parse_protocol(text: &str) -> Protocol {
    let upper = go_upper(text);
    match upper.as_ref() {
        "DOH" => Protocol::Doh,
        "DOT" => Protocol::Dot,
        "DOQ" => Protocol::Doq,
        _ => Protocol::Plain,
    }
}

pub fn validated_protocol(text: &str) -> Result<Protocol, String> {
    let upper = go_upper(text);
    match upper.as_ref() {
        "PLAIN" => Ok(Protocol::Plain),
        "DOH" => Ok(Protocol::Doh),
        "DOT" => Ok(Protocol::Dot),
        "DOQ" => Ok(Protocol::Doq),
        _ => Err(format!("unsupported protocol {}", go_quote(&upper))),
    }
}

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

pub fn parse_response_type(text: &str) -> ResponseType {
    match text {
        "NXDOMAIN" => ResponseType::NxDomain,
        "REFUSED" => ResponseType::Refused,
        "NODATA" => ResponseType::NoData,
        _ => ResponseType::CustomIp,
    }
}

pub fn parse_response_type_upper(text: &str) -> ResponseType {
    parse_response_type(&go_upper(text))
}

#[cfg(test)]
mod tests;
