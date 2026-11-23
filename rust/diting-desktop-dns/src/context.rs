use std::net::SocketAddr;
use std::time::Instant;

use diting_dns_wire::parse_question;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Transport {
    Udp,
    Tcp,
    Dot,
    Doh,
}

impl Transport {
    pub fn as_str(self) -> &'static str {
        match self {
            Transport::Udp => "udp",
            Transport::Tcp => "tcp",
            Transport::Dot => "dot",
            Transport::Doh => "doh",
        }
    }
}

#[derive(Debug, Clone)]
pub struct Question {
    pub name: String,
    pub qtype: u16,
    pub qclass: u16,
}

pub struct DnsContext {
    pub request: Vec<u8>,
    pub question: Question,
    pub client: Option<SocketAddr>,
    pub transport: Transport,
    pub client_name: String,
    pub client_id: String,
    pub group: String,
    pub started: Instant,
    pub response: Option<Vec<u8>>,
    pub stale_response: Option<Vec<u8>>,
    pub error: Option<String>,
    attributes: Vec<(String, String)>,
}

impl DnsContext {
    pub fn new(request: Vec<u8>, client: Option<SocketAddr>, transport: Transport) -> Option<Self> {
        let (question, _) = parse_question(&request, 12, false)?;
        Some(Self {
            request,
            question: Question {
                name: question.name,
                qtype: question.qtype,
                qclass: question.qclass,
            },
            client,
            transport,
            client_name: String::new(),
            client_id: String::new(),
            group: "default".to_string(),
            started: Instant::now(),
            response: None,
            stale_response: None,
            error: None,
            attributes: Vec::new(),
        })
    }

    pub fn set(&mut self, key: &str, value: impl Into<String>) {
        let value = value.into();
        if let Some(entry) = self.attributes.iter_mut().find(|(name, _)| name == key) {
            entry.1 = value;
        } else {
            self.attributes.push((key.to_string(), value));
        }
    }

    pub fn get(&self, key: &str) -> Option<&str> {
        self.attributes
            .iter()
            .find(|(name, _)| name == key)
            .map(|(_, value)| value.as_str())
    }

    pub fn ephemeral_port(&self) -> u16 {
        self.client.map(|address| address.port()).unwrap_or(0)
    }

    pub fn elapsed_ms(&self) -> f64 {
        self.started.elapsed().as_secs_f64() * 1000.0
    }

    pub fn attributes(&self) -> &[(String, String)] {
        &self.attributes
    }

    pub fn reply_with_rcode(&mut self, rcode: u8) {
        self.response =
            diting_dns_wire::build::MessageBuilder::reply_to(&self.request).and_then(|builder| {
                builder
                    .set_rcode(rcode)
                    .set_recursion_available(true)
                    .finish()
            });
    }

    pub fn fail_servfail(&mut self) {
        self.reply_with_rcode(RCODE_SERVFAIL);
    }

    pub fn udp_payload_size(&self) -> usize {
        diting_dns_wire::build::parse_opt(&self.request)
            .map(|opt| usize::from(opt.udp_size).clamp(512, 65535))
            .unwrap_or(512)
    }
}

pub const RCODE_SERVFAIL: u8 = 2;
pub const RCODE_NXDOMAIN: u8 = 3;
pub const RCODE_NOTIMP: u8 = 4;
pub const RCODE_REFUSED: u8 = 5;

#[cfg(test)]
mod tests {
    use super::*;
    use diting_dns_wire::build::MessageBuilder;

    fn query() -> Vec<u8> {
        MessageBuilder::query("example.com", 1, 1).finish().unwrap()
    }

    #[test]
    fn servfail_reply_echoes_the_question() {
        let mut ctx = DnsContext::new(query(), None, Transport::Udp).unwrap();
        ctx.fail_servfail();
        let response = ctx.response.unwrap();
        let header = diting_dns_wire::parse_header(&response).unwrap();
        assert!(header.is_response());
        assert_eq!((header.flags & 0x000f) as u8, RCODE_SERVFAIL);
        let (question, _) = diting_dns_wire::parse_question(&response, 12, false).unwrap();
        assert_eq!(question.name, "example.com.");
    }

    #[test]
    fn udp_payload_size_defaults_to_512() {
        let ctx = DnsContext::new(query(), None, Transport::Udp).unwrap();
        assert_eq!(ctx.udp_payload_size(), 512);
    }
}
