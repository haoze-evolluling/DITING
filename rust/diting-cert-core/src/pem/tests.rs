//! PEM: the round trip, the tolerant scan, and the column layout `pem.EncodeToMemory` had.

use super::*;

#[test]
fn round_trip_is_the_go_layout() {
    let der = vec![0x30, 0x03, 0x02, 0x01, 0x2a];
    let encoded = encode("CERTIFICATE", &der);
    assert!(encoded.starts_with("-----BEGIN CERTIFICATE-----\n"));
    assert!(encoded.ends_with("-----END CERTIFICATE-----\n"));
    let block = decode(&encoded).unwrap();
    assert_eq!(block.label, "CERTIFICATE");
    assert_eq!(block.der, der);
}

#[test]
fn base64_is_wrapped_at_64_columns() {
    let der: Vec<u8> = (0..130).map(|index| index as u8).collect();
    let encoded = encode("CERTIFICATE", &der);
    let body: Vec<&str> = encoded
        .lines()
        .filter(|line| !line.starts_with("-----"))
        .collect();
    assert!(body.len() > 1);
    for line in &body[..body.len() - 1] {
        assert_eq!(line.len(), 64, "{line}");
    }
    assert!(body[body.len() - 1].len() <= 64);
}

#[test]
fn leading_text_and_trailing_data_are_tolerated() {
    let block = encode("EC PRIVATE KEY", &[0x01, 0x02, 0x03]);
    let padded = format!("subject=/CN=whatever\n{block}extra text after the block\n");
    let decoded = decode(&padded).unwrap();
    assert_eq!(decoded.label, "EC PRIVATE KEY");
    assert_eq!(decoded.der, vec![0x01, 0x02, 0x03]);
}

#[test]
fn an_unterminated_or_broken_block_is_none() {
    assert!(decode("no pem here").is_none());
    assert!(decode("-----BEGIN CERTIFICATE-----\nAAAA\n").is_none());
    assert!(decode("-----BEGIN CERTIFICATE-----\n!!!!\n-----END CERTIFICATE-----\n").is_none());
}

#[test]
fn the_first_block_wins() {
    let first = encode("CERTIFICATE", &[0xaa]);
    let second = encode("CERTIFICATE", &[0xbb]);
    let decoded = decode(&format!("{first}{second}")).unwrap();
    assert_eq!(decoded.der, vec![0xaa]);
}
