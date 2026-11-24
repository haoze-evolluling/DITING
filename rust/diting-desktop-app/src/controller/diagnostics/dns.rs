use std::net::SocketAddr;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use diting_dns_wire::{
    MessageBuilder, ParsedMessage, RData, CLASS_IN, TYPE_A, TYPE_AAAA, TYPE_ANY, TYPE_CAA,
    TYPE_CNAME, TYPE_HTTPS, TYPE_MX, TYPE_NS, TYPE_PTR, TYPE_SOA, TYPE_SRV, TYPE_SVCB, TYPE_TXT,
};

pub struct ParsedAnswer {
    pub name: String,
    pub record_type: String,
    pub ttl: u32,
    pub value: String,
}

pub struct ParsedReply {
    pub rcode: u8,
    pub truncated: bool,
    pub answers: Vec<ParsedAnswer>,
}

/// 解析查询类型名称，同时返回展示用的大写名称。
pub fn parse_qtype(input: &str) -> Result<(u16, String), String> {
    let name = input.trim().to_ascii_uppercase();
    let name = if name.is_empty() {
        "A".to_string()
    } else {
        name
    };
    let code = match name.as_str() {
        "A" => TYPE_A,
        "AAAA" => TYPE_AAAA,
        "CNAME" => TYPE_CNAME,
        "TXT" => TYPE_TXT,
        "MX" => TYPE_MX,
        "NS" => TYPE_NS,
        "PTR" => TYPE_PTR,
        "SRV" => TYPE_SRV,
        "SOA" => TYPE_SOA,
        "HTTPS" => TYPE_HTTPS,
        "SVCB" => TYPE_SVCB,
        "CAA" => TYPE_CAA,
        "ANY" => TYPE_ANY,
        other => return Err(format!("不支持的查询类型: {other}")),
    };
    Ok((code, name))
}

pub fn build_query(domain: &str, qtype: u16) -> Result<Vec<u8>, String> {
    let id = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| (duration.subsec_nanos() & 0xffff) as u16)
        .unwrap_or(0x1234);
    MessageBuilder::query(domain, qtype, CLASS_IN)
        .set_id(id)
        .finish()
        .ok_or_else(|| "无法构造 DNS 查询报文".to_string())
}

pub fn parse_reply(wire: &[u8]) -> Option<ParsedReply> {
    let message = ParsedMessage::parse(wire)?;
    let answers = message
        .answers
        .iter()
        .map(|record| ParsedAnswer {
            name: record.name.trim_end_matches('.').to_string(),
            record_type: record_type_name(record.rtype),
            ttl: record.ttl,
            value: format_rdata(&record.rdata),
        })
        .collect();
    Some(ParsedReply {
        rcode: message.rcode(),
        truncated: message.flags & 0x0200 != 0,
        answers,
    })
}

pub fn rcode_name(rcode: u8) -> String {
    match rcode {
        0 => "NOERROR".to_string(),
        1 => "FORMERR".to_string(),
        2 => "SERVFAIL".to_string(),
        3 => "NXDOMAIN".to_string(),
        4 => "NOTIMP".to_string(),
        5 => "REFUSED".to_string(),
        6 => "YXDOMAIN".to_string(),
        7 => "YXRRSET".to_string(),
        8 => "NXRRSET".to_string(),
        9 => "NOTAUTH".to_string(),
        10 => "NOTZONE".to_string(),
        other => format!("RCODE {other}"),
    }
}

fn record_type_name(rtype: u16) -> String {
    let name = match rtype {
        TYPE_A => "A",
        TYPE_NS => "NS",
        TYPE_CNAME => "CNAME",
        TYPE_SOA => "SOA",
        TYPE_PTR => "PTR",
        TYPE_MX => "MX",
        TYPE_TXT => "TXT",
        TYPE_AAAA => "AAAA",
        TYPE_SRV => "SRV",
        TYPE_SVCB => "SVCB",
        TYPE_HTTPS => "HTTPS",
        TYPE_CAA => "CAA",
        TYPE_ANY => "ANY",
        _ => "",
    };
    if name.is_empty() {
        format!("TYPE{rtype}")
    } else {
        name.to_string()
    }
}

fn format_rdata(rdata: &RData) -> String {
    let trim = |value: &str| value.trim_end_matches('.').to_string();
    match rdata {
        RData::A(address) => address.to_string(),
        RData::Aaaa(address) => address.to_string(),
        RData::Cname(name) | RData::Ptr(name) | RData::Ns(name) => trim(name),
        RData::Soa {
            mname,
            rname,
            serial,
            ..
        } => format!("{} {} {serial}", trim(mname), trim(rname)),
        RData::Mx {
            preference,
            exchange,
        } => format!("{preference} {}", trim(exchange)),
        RData::Txt(values) => values
            .iter()
            .map(|value| String::from_utf8_lossy(value).into_owned())
            .collect::<Vec<_>>()
            .join(" "),
        RData::Srv {
            priority,
            weight,
            port,
            target,
        } => format!("{priority} {weight} {port} {}", trim(target)),
        RData::Https(data) | RData::Svcb(data) => {
            if data.target.is_empty() {
                data.priority.to_string()
            } else {
                format!("{} {}", data.priority, trim(&data.target))
            }
        }
        RData::Hinfo { cpu, os } => format!("{cpu} {os}"),
        RData::Caa { flags, tag, value } => {
            format!("{flags} {tag} \"{}\"", String::from_utf8_lossy(value))
        }
        RData::Naptr {
            order,
            preference,
            flags,
            services,
            regexp,
            replacement,
        } => format!(
            "{order} {preference} \"{flags}\" \"{services}\" \"{regexp}\" {}",
            trim(replacement)
        ),
        RData::Raw(bytes) => bytes
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<Vec<_>>()
            .join(""),
    }
}

/// 把监听地址折算为可直连的回环地址。
pub fn local_endpoint(listen: &str) -> Option<SocketAddr> {
    let trimmed = listen.trim();
    let text = if let Some(rest) = trimmed.strip_prefix("0.0.0.0:") {
        format!("127.0.0.1:{rest}")
    } else if let Some(rest) = trimmed.strip_prefix("[::]:") {
        format!("[::1]:{rest}")
    } else {
        trimmed.to_string()
    };
    text.parse().ok()
}

pub async fn query_udp(
    endpoint: SocketAddr,
    query: &[u8],
    timeout: Duration,
) -> Result<Vec<u8>, String> {
    let bind = if endpoint.is_ipv4() {
        "0.0.0.0:0"
    } else {
        "[::]:0"
    };
    let socket = tokio::net::UdpSocket::bind(bind)
        .await
        .map_err(|error| format!("创建套接字失败: {error}"))?;
    socket
        .connect(endpoint)
        .await
        .map_err(|error| format!("连接本机 DNS 失败: {error}"))?;
    socket
        .send(query)
        .await
        .map_err(|error| format!("发送查询失败: {error}"))?;
    let mut buffer = [0u8; 4096];
    let size = tokio::time::timeout(timeout, socket.recv(&mut buffer))
        .await
        .map_err(|_| "等待本机 DNS 响应超时".to_string())?
        .map_err(|error| format!("读取响应失败: {error}"))?;
    Ok(buffer[..size].to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qtypes_are_normalized() {
        assert_eq!(parse_qtype("").unwrap(), (TYPE_A, "A".to_string()));
        assert_eq!(
            parse_qtype(" aaaa ").unwrap(),
            (TYPE_AAAA, "AAAA".to_string())
        );
        assert!(parse_qtype("BOGUS").is_err());
    }

    #[test]
    fn query_round_trips_through_the_parser() {
        let query = build_query("example.com", TYPE_A).unwrap();
        assert_eq!(query.len(), 12 + 13 + 4);

        let mut reply = query.clone();
        reply[2] = 0x81;
        reply[3] = 0x80;
        reply[7] = 1;
        reply.extend_from_slice(&[0xc0, 0x0c]);
        reply.extend_from_slice(&TYPE_A.to_be_bytes());
        reply.extend_from_slice(&CLASS_IN.to_be_bytes());
        reply.extend_from_slice(&300u32.to_be_bytes());
        reply.extend_from_slice(&4u16.to_be_bytes());
        reply.extend_from_slice(&[203, 0, 113, 7]);

        let parsed = parse_reply(&reply).expect("reply parses");
        assert_eq!(parsed.rcode, 0);
        assert!(!parsed.truncated);
        assert_eq!(parsed.answers.len(), 1);
        assert_eq!(parsed.answers[0].name, "example.com");
        assert_eq!(parsed.answers[0].record_type, "A");
        assert_eq!(parsed.answers[0].ttl, 300);
        assert_eq!(parsed.answers[0].value, "203.0.113.7");
    }

    #[test]
    fn rcodes_have_readable_names() {
        assert_eq!(rcode_name(0), "NOERROR");
        assert_eq!(rcode_name(3), "NXDOMAIN");
        assert_eq!(rcode_name(5), "REFUSED");
        assert_eq!(rcode_name(42), "RCODE 42");
    }

    #[test]
    fn wildcard_listeners_map_to_loopback() {
        assert_eq!(
            local_endpoint("0.0.0.0:53"),
            Some("127.0.0.1:53".parse().unwrap())
        );
        assert_eq!(local_endpoint("[::]:53"), Some("[::1]:53".parse().unwrap()));
        assert_eq!(
            local_endpoint("127.0.0.1:5354"),
            Some("127.0.0.1:5354".parse().unwrap())
        );
        assert_eq!(local_endpoint("not-an-address"), None);
    }
}
