//! The two name tables.

use super::*;

#[test]
fn protocol_folds_case_and_defaults_to_plain() {
    for (text, expected) in [
        ("DOH", Protocol::Doh),
        ("doh", Protocol::Doh),
        ("DoH", Protocol::Doh),
        ("DOT", Protocol::Dot),
        ("DOQ", Protocol::Doq),
        ("PLAIN", Protocol::Plain),
        ("plain", Protocol::Plain),
        ("", Protocol::Plain),
        ("HYPER", Protocol::Plain),
        // `ParseProtocol` upper-cases but does not trim.
        (" dot ", Protocol::Plain),
    ] {
        assert_eq!(parse_protocol(text), expected, "{text}");
    }
}

#[test]
fn the_strict_table_rejects_unknown_names_with_the_original_text() {
    assert_eq!(validated_protocol("plain").unwrap(), Protocol::Plain);
    assert_eq!(validated_protocol("DoH").unwrap(), Protocol::Doh);
    // The caller upper-cased before validating, so the error carries the upper-cased name.
    assert_eq!(
        validated_protocol("hyper").unwrap_err(),
        "unsupported protocol \"HYPER\""
    );
    assert_eq!(
        validated_protocol("").unwrap_err(),
        "unsupported protocol \"\""
    );
}

#[test]
fn response_type_is_case_sensitive() {
    for (text, expected) in [
        ("NXDOMAIN", ResponseType::NxDomain),
        ("REFUSED", ResponseType::Refused),
        ("NODATA", ResponseType::NoData),
        ("CUSTOM_IP", ResponseType::CustomIp),
        ("nxdomain", ResponseType::CustomIp),
        ("nxDomain", ResponseType::CustomIp),
        ("", ResponseType::CustomIp),
    ] {
        assert_eq!(parse_response_type(text), expected, "{text}");
    }
    // The config path upper-cases first, so `"nxdomain"` there is still NXDOMAIN.
    assert_eq!(
        parse_response_type_upper("nxdomain"),
        ResponseType::NxDomain
    );
    assert_eq!(
        parse_response_type_upper(" Refused "),
        ResponseType::CustomIp
    );
}

#[test]
fn codes_round_trip() {
    for protocol in [Protocol::Plain, Protocol::Doh, Protocol::Dot, Protocol::Doq] {
        assert_eq!(Protocol::from_code(protocol.code()), Some(protocol));
        assert!(!protocol.name().is_empty());
    }
    for response in [
        ResponseType::CustomIp,
        ResponseType::NxDomain,
        ResponseType::Refused,
        ResponseType::NoData,
    ] {
        assert_eq!(ResponseType::from_code(response.code()), Some(response));
    }
    assert_eq!(Protocol::from_code(4), None);
    assert_eq!(ResponseType::from_code(-1), None);
}
