//! Replays the fixtures generated from the pre-migration Go implementation
//! (`android/engine/zz_fixture_gen_test.go` before it was deleted), so the kernel is compared
//! against the code it replaced rather than against a second Rust implementation.
//!
//! * `address.tsv` - `encodeSocksAddress` over the target corpus.
//! * `reply.tsv` - `readSocksReply` over reply streams (including truncated ones).
//! * `datagram.tsv` - `decodeSocksDatagramAddress` over datagram bodies.
//! * `handshake.tsv` - the `socksNegotiate` + `socksConnect` byte stream and error text.
//! * `http.tsv` - the bytes `httpConnect` wrote (`http.Request.Write` output). The reply handling
//!   stays Go's `http.ReadResponse`, so only the request column is replayed here.
//! * `config.tsv` - `parseOutboundProxyConfig` over the decoded field corpus.

use std::fs;

use diting_proxy_core::addr::join_host_port;
use diting_proxy_core::config::{normalize, ProxyConfig};
use diting_proxy_core::http::connect_request;
use diting_proxy_core::socks5::{
    self, address, auth_reply, auth_request, greeting, method_reply, parse_datagram, parse_reply,
    request, AuthMethod, ReplyParse,
};

fn fixture(name: &str) -> Vec<Vec<String>> {
    let path = format!("{}/tests/fixtures/{name}", env!("CARGO_MANIFEST_DIR"));
    let body = fs::read_to_string(&path).unwrap_or_else(|err| panic!("{path}: {err}"));
    body.lines()
        .filter(|line| !line.is_empty())
        .map(|line| line.split('\t').map(str::to_string).collect())
        .collect()
}

fn unhex(text: &str) -> Vec<u8> {
    assert!(text.len().is_multiple_of(2), "{text:?} is not hex");
    (0..text.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&text[index..index + 2], 16).unwrap())
        .collect()
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

fn text(hex_text: &str) -> String {
    String::from_utf8(unhex(hex_text)).unwrap()
}

#[test]
fn address_corpus_matches_encode_socks_address() {
    let rows = fixture("address.tsv");
    assert!(rows.len() > 10);
    for row in rows {
        let (target, expected) = (&row[0], &row[1]);
        let actual = match address(target) {
            Ok(bytes) => hex(&bytes),
            Err(err) => format!("err:{err}"),
        };
        assert_eq!(&actual, expected, "target {target:?}");
    }
}

#[test]
fn reply_corpus_matches_read_socks_reply() {
    for row in fixture("reply.tsv") {
        let stream = unhex(&row[0]);
        let expected = &row[1];
        let actual = match read_reply(&stream) {
            Ok(address) => address,
            Err(err) => format!("err:{err}"),
        };
        assert_eq!(&actual, expected, "stream {:?}", row[0]);
    }
}

/// The Go reader: read exactly what the parser asks for, wrap the first read only.
fn read_reply(stream: &[u8]) -> Result<String, String> {
    let mut read = 0;
    loop {
        match parse_reply(&stream[..read]) {
            Err(err) => return Err(err),
            Ok(ReplyParse::Done { address }) => return Ok(address),
            Ok(ReplyParse::NeedMore(need)) => {
                if need > stream.len() {
                    let available = stream.len() - read;
                    let reason = if available == 0 {
                        "EOF"
                    } else {
                        "unexpected EOF"
                    };
                    return Err(if read == 0 {
                        format!("SOCKS5 response: {reason}")
                    } else {
                        reason.to_string()
                    });
                }
                read = need;
            }
        }
    }
}

#[test]
fn datagram_corpus_matches_decode_socks_datagram_address() {
    for row in fixture("datagram.tsv") {
        let raw = unhex(&row[0]);
        if row.len() == 2 {
            let expected = &row[1];
            let actual = match parse_datagram(&raw) {
                Ok(view) => format!("{}#{}", view.address, view.offset),
                Err(err) => format!("err:{err}"),
            };
            assert_eq!(&actual, expected, "datagram {:?}", row[0]);
            continue;
        }
        let view = parse_datagram(&raw).expect("fixture row must decode");
        let expected_address = join_host_port(&row[1], row[2].parse().unwrap());
        assert_eq!(view.address, expected_address, "datagram {:?}", row[0]);
        assert_eq!(view.offset.to_string(), row[3]);
        assert_eq!(hex(&raw[view.offset..]), row[4]);
    }
}

#[test]
fn handshake_corpus_matches_the_go_handshake() {
    for row in fixture("handshake.tsv") {
        let username = text(&row[0]);
        let password = text(&row[1]);
        let command: u8 = row[2].parse().unwrap();
        let target = text(&row[3]);
        let script: Vec<&str> = row[4].split('|').collect();
        let expected_written = &row[5];
        let expected_result = &row[6];

        let (written, result) = replay_handshake(&username, &password, command, &target, &script);
        assert_eq!(&hex(&written), expected_written, "handshake {:?}", row[3]);
        assert_eq!(&result, expected_result, "handshake {:?}", row[3]);
    }
}

fn replay_handshake(
    username: &str,
    password: &str,
    command: u8,
    target: &str,
    script: &[&str],
) -> (Vec<u8>, String) {
    let mut written = greeting(username, password);
    let method = match method_reply(&unhex(script[0])) {
        Ok(method) => method,
        Err(err) => return (written, err),
    };
    if let AuthMethod::UserPass = method {
        written.extend_from_slice(&auth_request(username, password));
        if let Err(err) = auth_reply(&unhex(script[1])) {
            return (written, err);
        }
    }
    let frame = match request(command, target) {
        Ok(frame) => frame,
        Err(err) => return (written, err),
    };
    written.extend_from_slice(&frame);
    let reply = unhex(script[2]);
    let result = match read_reply(&reply) {
        Ok(_) => String::new(),
        Err(err) => err,
    };
    (written, result)
}

#[test]
fn http_corpus_matches_connect_request_bytes() {
    for row in fixture("http.tsv") {
        let username = text(&row[0]);
        let password = text(&row[1]);
        let target = text(&row[2]);
        let expected_written = &row[4];
        let written = connect_request(&target, &username, &password);
        assert_eq!(&hex(&written), expected_written, "CONNECT {target}");
        // The reply column (`row[3]`) is input for Go's `http.ReadResponse`; the result column is
        // produced there too, so only the request bytes are replayed.
        assert_eq!(row.len(), 6);
    }
}

#[test]
fn config_corpus_matches_parse_outbound_proxy_config() {
    for row in fixture("config.tsv") {
        let input = ProxyConfig {
            enabled: row[1] == "1",
            protocol: text(&row[2]),
            host: text(&row[3]),
            port: row[4].parse().unwrap(),
            username: text(&row[5]),
            password: text(&row[6]),
            scope: text(&row[7]),
            uids: if row[8] == "-" {
                Vec::new()
            } else {
                row[8].split(',').map(|uid| uid.parse().unwrap()).collect()
            },
        };
        let actual = match normalize(input) {
            Ok(config) => {
                let uids = if config.uids.is_empty() {
                    "-".to_string()
                } else {
                    config
                        .uids
                        .iter()
                        .map(i64::to_string)
                        .collect::<Vec<_>>()
                        .join(",")
                };
                format!(
                    "ok\t{}\t{}\t{}\t{}\t{}",
                    hex(config.protocol.as_bytes()),
                    hex(config.host.as_bytes()),
                    config.port,
                    hex(config.scope.as_bytes()),
                    uids
                )
            }
            Err(err) => format!("err:{err}"),
        };
        // A successful row spreads its result over the remaining columns (`ok`, protocol, host,
        // port, scope, uids); an error row keeps it in one.
        assert_eq!(actual, row[9..].join("	"), "config row {:?}", row[2]);
    }
}

#[test]
fn udp_associate_request_is_the_constant_the_fixture_wrote() {
    // The `socksConnect(0x03, "0.0.0.0:0")` row of handshake.tsv ends with these bytes.
    assert_eq!(
        hex(&request(0x03, "0.0.0.0:0").unwrap()),
        "05030001000000000000"
    );
    assert_eq!(
        hex(&socks5::udp_associate_request()),
        "05030001000000000000"
    );
}
