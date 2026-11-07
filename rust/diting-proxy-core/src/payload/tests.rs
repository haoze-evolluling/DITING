//! The envelope: round trips, the rejection rules and the shapes the Go decoder reads.

use super::*;
use crate::config::SCOPE_APPS;

fn reply_response(bytes: &[u8]) -> Vec<u8> {
    encode_response(handle(Request::SocksReply {
        frame: bytes.to_vec(),
    }))
}

/// Reads response bodies field by field so the assertions do not hard-code byte offsets.
struct Cursor<'a> {
    payload: &'a [u8],
    position: usize,
}

impl<'a> Cursor<'a> {
    fn new(payload: &'a [u8]) -> Self {
        Cursor {
            payload,
            position: 0,
        }
    }

    fn at_end(&self) -> bool {
        self.position == self.payload.len()
    }

    fn take(&mut self, length: usize) -> &'a [u8] {
        let slice = &self.payload[self.position..self.position + length];
        self.position += length;
        slice
    }

    fn u8(&mut self) -> u8 {
        self.take(1)[0]
    }

    fn u32(&mut self) -> u32 {
        u32::from_le_bytes(self.take(4).try_into().unwrap())
    }

    fn i64(&mut self) -> i64 {
        i64::from_le_bytes(self.take(8).try_into().unwrap())
    }

    fn text(&mut self) -> String {
        let length = self.u32() as usize;
        String::from_utf8(self.take(length).to_vec()).unwrap()
    }
}

#[test]
fn every_op_round_trips() {
    let requests = vec![
        Request::Configure(ProxyConfig {
            enabled: true,
            protocol: "socks5".to_string(),
            host: "127.0.0.1".to_string(),
            port: 1080,
            username: "u".to_string(),
            password: "p".to_string(),
            scope: SCOPE_APPS.to_string(),
            uids: vec![1, 2],
        }),
        Request::SocksGreeting {
            username: "u".to_string(),
            password: "p".to_string(),
        },
        Request::SocksMethodReply {
            reply: vec![0x05, 0x00],
        },
        Request::SocksAuth {
            username: "u".to_string(),
            password: "p".to_string(),
        },
        Request::SocksAuthReply {
            reply: vec![0x01, 0x00],
        },
        Request::SocksRequest {
            command: 0x01,
            target: "example.com:80".to_string(),
        },
        Request::SocksUdpAssociate,
        Request::SocksReply {
            frame: vec![0x05, 0x00, 0x00, 0x01, 1, 2, 3, 4, 0, 80],
        },
        Request::SocksDatagram {
            target: "1.2.3.4:53".to_string(),
            payload: vec![0xaa, 0xbb],
        },
        Request::SocksDatagramParse {
            datagram: vec![0x01, 1, 2, 3, 4, 0, 53],
        },
        Request::HttpConnect {
            target: "example.com:443".to_string(),
            username: "u".to_string(),
            password: "p".to_string(),
        },
    ];
    for request in requests {
        let encoded = encode_request(&request);
        assert_eq!(decode_request(&encoded), Some(request));
    }
}

#[test]
fn malformed_envelopes_are_rejected() {
    // Wrong layout byte, unknown opcode, truncated field, trailing bytes, non-UTF-8 text.
    assert_eq!(decode_request(&[]), None);
    assert_eq!(decode_request(&[2, OP_SOCKS_UDP_ASSOCIATE]), None);
    assert_eq!(decode_request(&[LAYOUT_VERSION, 42]), None);
    assert_eq!(
        decode_request(&[LAYOUT_VERSION, OP_SOCKS_UDP_ASSOCIATE, 0]),
        None
    );

    let mut truncated = encode_request(&Request::SocksRequest {
        command: 1,
        target: "h:1".to_string(),
    });
    truncated.pop();
    assert_eq!(decode_request(&truncated), None);

    let mut bad_text = vec![LAYOUT_VERSION, OP_SOCKS_GREETING];
    push_bytes(&mut bad_text, &[0xff, 0xfe]);
    push_bytes(&mut bad_text, b"p");
    assert_eq!(decode_request(&bad_text), None);
}

#[test]
fn configure_response_uses_the_normalized_fields() {
    let request = Request::Configure(ProxyConfig {
        enabled: true,
        protocol: " SOCKS5 ".to_string(),
        host: "::ffff:127.0.0.1".to_string(),
        port: 1080,
        username: String::new(),
        password: String::new(),
        scope: "APPS".to_string(),
        uids: vec![7, 0, 7],
    });
    let encoded = encode_response(handle(request));
    let mut cursor = Cursor::new(&encoded);
    assert_eq!(cursor.u8(), 0, "status byte");
    // enabled | protocol | host | port | scope | uid count + ids
    assert_eq!(cursor.u8(), 1);
    assert_eq!(cursor.text(), "socks5");
    assert_eq!(cursor.text(), "127.0.0.1");
    assert_eq!(cursor.i64(), 1080);
    assert_eq!(cursor.text(), "apps");
    assert_eq!(cursor.u32(), 1);
    assert_eq!(cursor.i64(), 7);
    assert!(cursor.at_end());
}

#[test]
fn op_errors_come_back_as_a_message() {
    let encoded = encode_response(handle(Request::SocksRequest {
        command: 1,
        target: "nocolon".to_string(),
    }));
    assert_eq!(encoded[0], 1);
    let length = u32::from_le_bytes(encoded[1..5].try_into().unwrap()) as usize;
    assert_eq!(length, encoded.len() - 5);
    assert_eq!(
        std::str::from_utf8(&encoded[5..]).unwrap(),
        "invalid target \"nocolon\": address nocolon: missing port in address"
    );
}

#[test]
fn reply_response_distinguishes_done_from_need_more() {
    let done = reply_response(&[0x05, 0x00, 0x00, 0x01, 1, 2, 3, 4, 0, 80]);
    let mut cursor = Cursor::new(&done);
    assert_eq!(cursor.u8(), 0);
    assert_eq!(cursor.u8(), 0);
    assert_eq!(cursor.text(), "1.2.3.4:80");
    assert!(cursor.at_end(), "{done:?}");

    let more = reply_response(&[0x05, 0x00]);
    let mut cursor = Cursor::new(&more);
    assert_eq!(cursor.u8(), 0);
    assert_eq!(cursor.u8(), 1);
    assert_eq!(cursor.u32(), 4);
    assert!(cursor.at_end(), "{more:?}");
}

#[test]
fn datagram_parse_response_carries_address_flag_and_offset() {
    let encoded = encode_response(handle(Request::SocksDatagramParse {
        datagram: vec![0x01, 1, 2, 3, 4, 0, 53, 0xaa],
    }));
    let mut cursor = Cursor::new(&encoded);
    assert_eq!(cursor.u8(), 0);
    assert_eq!(cursor.text(), "1.2.3.4:53");
    assert_eq!(cursor.u8(), 1);
    assert_eq!(cursor.u32(), 7);
    assert!(cursor.at_end());
}

#[test]
fn unit_and_method_bodies() {
    let encoded = encode_response(handle(Request::SocksMethodReply {
        reply: vec![0x05, 0x02],
    }));
    assert_eq!(encoded, vec![0, 2]);

    let encoded = encode_response(handle(Request::SocksAuthReply {
        reply: vec![0x01, 0x00],
    }));
    assert_eq!(encoded, vec![0]);

    let encoded = encode_response(handle(Request::SocksUdpAssociate));
    assert_eq!(encoded[0], 0);
    assert_eq!(&encoded[5..], &[0x05, 0x03, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
}
