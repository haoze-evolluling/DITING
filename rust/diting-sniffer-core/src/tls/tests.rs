//! Sniffer cases pinned independently of the corpus: the clamping rules and the exact bytes the
//! Go parser returned for hand-built handshakes.

use crate::tls::parse_client_hello_sni;

/// Builds a ClientHello record around `extensions`, the way the corpus generator did.
fn client_hello(extensions: &[u8]) -> Vec<u8> {
    let mut body = vec![0x01, 0, 0, 0, 0x03, 0x03];
    body.extend_from_slice(&[0u8; 32]);
    body.push(0x00); // session id length
    body.extend_from_slice(&[0x00, 0x02, 0x13, 0x01]); // cipher suites
    body.extend_from_slice(&[0x01, 0x00]); // compression methods
    body.extend_from_slice(&(extensions.len() as u16).to_be_bytes());
    body.extend_from_slice(extensions);
    let handshake_len = body.len() - 4;
    body[1] = (handshake_len >> 16) as u8;
    body[2] = (handshake_len >> 8) as u8;
    body[3] = handshake_len as u8;
    let mut record = vec![0x16, 0x03, 0x01];
    record.extend_from_slice(&(body.len() as u16).to_be_bytes());
    record.extend_from_slice(&body);
    record
}

/// One SNI extension around a single host_name entry.
fn sni_extension(host: &[u8]) -> Vec<u8> {
    let mut entry = vec![0x00];
    entry.extend_from_slice(&(host.len() as u16).to_be_bytes());
    entry.extend_from_slice(host);
    let mut list = (entry.len() as u16).to_be_bytes().to_vec();
    list.extend_from_slice(&entry);
    let mut extension = vec![0x00, 0x00];
    extension.extend_from_slice(&(list.len() as u16).to_be_bytes());
    extension.extend_from_slice(&list);
    extension
}

#[test]
fn reads_a_single_sni() {
    let record = client_hello(&sni_extension(b"example.com"));
    assert_eq!(parse_client_hello_sni(&record), b"example.com");
}

#[test]
fn keeps_the_bytes_as_sent() {
    let record = client_hello(&sni_extension(b"Ads.Example.COM"));
    assert_eq!(parse_client_hello_sni(&record), b"Ads.Example.COM");
}

#[test]
fn ignores_extensions_before_the_sni() {
    let alpn = [0x00, 0x10, 0x00, 0x05, 0x00, 0x03, 0x02, b'h', b'2'];
    let mut extensions = alpn.to_vec();
    extensions.extend_from_slice(&sni_extension(b"alpn.example"));
    assert_eq!(
        parse_client_hello_sni(&client_hello(&extensions)),
        b"alpn.example"
    );
}

#[test]
fn returns_the_first_entry_of_a_multi_entry_list() {
    let mut entries = sni_extension(b"first.example");
    // Rewrite the extension into a list with two entries by appending a second one.
    let second = sni_extension(b"second.example");
    entries.extend_from_slice(&second[4..]);
    let list_len = entries.len() - 4;
    entries[2] = (list_len >> 8) as u8;
    entries[3] = list_len as u8;
    assert_eq!(
        parse_client_hello_sni(&client_hello(&entries)),
        b"first.example"
    );
}

#[test]
fn rejects_non_tls_records() {
    assert_eq!(parse_client_hello_sni(&[]), b"");
    assert_eq!(parse_client_hello_sni(&[0x16, 0x03, 0x01]), b"");
    let mut record = client_hello(&sni_extension(b"example.com"));
    record[0] = 0x17;
    assert_eq!(parse_client_hello_sni(&record), b"");
}

#[test]
fn clamps_a_record_length_that_runs_past_the_peek() {
    let mut record = client_hello(&sni_extension(b"example.com"));
    record[3] = 0xff;
    record[4] = 0xff;
    assert_eq!(parse_client_hello_sni(&record), b"example.com");
}

#[test]
fn rejects_a_session_length_that_runs_past_the_peek() {
    let mut record = client_hello(&sni_extension(b"example.com"));
    // body starts at 5, ch at 9; session length is ch[34].
    record[9 + 34] = 0xff;
    assert_eq!(parse_client_hello_sni(&record), b"");
}

#[test]
fn returns_empty_without_an_sni_extension() {
    let alpn = [0x00, 0x10, 0x00, 0x05, 0x00, 0x03, 0x02, b'h', b'2'];
    assert_eq!(parse_client_hello_sni(&client_hello(&alpn)), b"");
    assert_eq!(parse_client_hello_sni(&client_hello(&[])), b"");
}

#[test]
fn rejects_an_sni_entry_that_is_not_a_host_name() {
    let mut extension = sni_extension(b"example.com");
    // list starts at extension[4]; entry type at extension[6].
    extension[6] = 0x01;
    assert_eq!(parse_client_hello_sni(&client_hello(&extension)), b"");
}

#[test]
fn rejects_a_truncated_sni_list() {
    let mut extension = sni_extension(b"example.com");
    extension[5] = 0xff;
    assert_eq!(parse_client_hello_sni(&client_hello(&extension)), b"");
}

#[test]
fn accepts_an_empty_host_name() {
    assert_eq!(
        parse_client_hello_sni(&client_hello(&sni_extension(b""))),
        b""
    );
}
