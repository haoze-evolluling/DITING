//! The C ABI, called the way Dart calls it: one payload in, one payload out.

use super::*;

unsafe fn call(
    entry: unsafe extern "C" fn(*const u8, usize, *mut usize) -> *mut u8,
    payload: &[u8],
) -> Option<Vec<u8>> {
    let mut out_len: usize = 0;
    let pointer = entry(payload.as_ptr(), payload.len(), &mut out_len);
    if pointer.is_null() {
        return None;
    }
    let bytes = std::slice::from_raw_parts(pointer, out_len).to_vec();
    diting_dns_config_core_free(pointer, out_len);
    Some(bytes)
}

fn body_of(bytes: &Option<Vec<u8>>) -> Reader<'_> {
    let bytes = bytes.as_ref().expect("payload");
    let mut reader = Reader::new(bytes);
    assert_eq!(reader.u32(), Some(super::MAGIC));
    assert_eq!(reader.u32(), Some(super::ABI_VERSION));
    reader
}

fn tunnel_payload() -> Vec<u8> {
    let mut writer = Writer::new();
    writer.u8(0b1_0001);
    writer.string("single");
    writer.string("preset_alidns_dns");
    writer.strings(&[]);
    writer.strings(&[]);
    writer.strings(&[]);
    writer.opt_string(None);
    writer.strings(&["preset_alidns".to_string()]);
    writer.opt_string(None);
    writer.string("nxdomain");
    writer.string("limit_max_ttl");
    writer.i32(3600);
    writer.i32(3600);
    writer.i32(60);
    writer.i32(300);
    writer.i32(5);
    writer.i32(60);
    writer.i32(300);
    writer.u32(1);
    writer.string("preset_alidns_dns");
    writer.string("阿里云");
    writer.string("DNS");
    writer.string("");
    writer.string("223.5.5.5");
    writer.i32(53);
    writer.u32(1);
    writer.string("preset_alidns");
    writer.string("阿里云");
    writer.string("223.5.5.5");
    writer.finish()
}

#[test]
fn tunnel_entry_returns_mode_document_and_rows() {
    let bytes = unsafe { call(diting_dns_config_core_tunnel, &tunnel_payload()) };
    let mut reader = body_of(&bytes);
    assert_eq!(reader.string().as_deref(), Some("single"));
    let document = reader.string().expect("document");
    assert!(document.contains(r#""mode":"single""#));
    assert!(document.contains(r#""server":"223.5.5.5:53""#));
    assert_eq!(reader.u32(), Some(1));
    assert_eq!(reader.string().as_deref(), Some("preset_alidns_dns"));
    assert_eq!(reader.string().as_deref(), Some("阿里云"));
    assert_eq!(reader.string().as_deref(), Some("DNS"));
    assert_eq!(reader.string().as_deref(), Some(""));
    assert_eq!(reader.string().as_deref(), Some("223.5.5.5"));
    assert_eq!(reader.i32(), Some(53));
    assert_eq!(reader.u32(), Some(1));
    assert_eq!(reader.string().as_deref(), Some("preset_alidns"));
    assert_eq!(reader.string().as_deref(), Some("阿里云"));
    assert_eq!(reader.string().as_deref(), Some("223.5.5.5"));
}

#[test]
fn server_entry_returns_port_mode_document_and_upstreams() {
    let mut writer = Writer::new();
    writer.u8(0b010);
    writer.string("primary_backup");
    writer.string("preset_cloudflare_doh");
    writer.strings(&[]);
    writer.strings(&[]);
    writer.strings(&[
        "preset_cloudflare_doh".to_string(),
        "preset_alidns_dns".to_string(),
    ]);
    writer.i32(1053);
    writer.string("balanced");
    writer.string("nxdomain");
    writer.i32(5);
    writer.i32(60);
    writer.i32(300);
    writer.opt_string(None);
    writer.u32(2);
    writer.string("preset_alidns_dns");
    writer.string("阿里云");
    writer.string("DNS");
    writer.string("223.5.5.5");
    writer.i32(53);
    writer.string("preset_cloudflare_doh");
    writer.string("Cloudflare");
    writer.string("DOH");
    writer.string("https://cloudflare-dns.com/dns-query");
    writer.i32(443);
    let bytes = unsafe { call(diting_dns_config_core_server, &writer.finish()) };
    let mut reader = body_of(&bytes);
    assert_eq!(reader.i32(), Some(1053));
    assert_eq!(reader.string().as_deref(), Some("primary_backup"));
    let document = reader.string().expect("document");
    assert!(document.contains(r#""mode":"primary_backup""#));
    assert!(document.contains(r#""url":"https://cloudflare-dns.com/dns-query""#));
    assert_eq!(reader.u32(), Some(2));
    assert_eq!(reader.string().as_deref(), Some("preset_cloudflare_doh"));
    assert_eq!(reader.string().as_deref(), Some("Cloudflare"));
    assert_eq!(reader.string().as_deref(), Some("DOH"));
    assert_eq!(
        reader.string().as_deref(),
        Some("https://cloudflare-dns.com/dns-query")
    );
    assert_eq!(reader.i32(), Some(443));
    assert_eq!(reader.string().as_deref(), Some("preset_alidns_dns"));
    assert_eq!(reader.string().as_deref(), Some("阿里云"));
    assert_eq!(reader.string().as_deref(), Some("DNS"));
    assert_eq!(reader.string().as_deref(), Some("223.5.5.5"));
    assert_eq!(reader.i32(), Some(53));
}

#[test]
fn provider_ops_cover_split_parse_encode_upsert_and_join() {
    let mut split = Writer::new();
    split.u8(OP_SPLIT_ADDRESS);
    split.string("DOT");
    split.string("dot.example:8853");
    let bytes = unsafe { call(diting_dns_config_core_providers, &split.finish()) };
    let mut reader = body_of(&bytes);
    assert_eq!(reader.string().as_deref(), Some(""));
    assert_eq!(reader.string().as_deref(), Some("dot.example"));
    assert_eq!(reader.i32(), Some(8853));

    let mut parse = Writer::new();
    parse.u8(OP_PARSE_PROVIDERS);
    parse.opt_string(Some(
        r#"[{"id":"a","name":"A","protocol":"DOT","url":"","host":"h","port":853}]"#,
    ));
    let bytes = unsafe { call(diting_dns_config_core_providers, &parse.finish()) };
    let mut reader = body_of(&bytes);
    assert_eq!(reader.u32(), Some(1));
    assert_eq!(reader.string().as_deref(), Some("a"));

    let mut encode = Writer::new();
    encode.u8(OP_ENCODE_PROVIDERS);
    encode.u32(1);
    encode.string("user_1");
    encode.string("自建 DoH");
    encode.string("DOH");
    encode.string("https://dns.example/query");
    encode.string("");
    encode.i32(853);
    let bytes = unsafe { call(diting_dns_config_core_providers, &encode.finish()) };
    let json = body_of(&bytes).string().expect("json");
    assert!(json.contains(r#""protocol":"DOH""#));
    assert!(json.contains(r#""name":"自建 DoH""#));

    let mut upsert = Writer::new();
    upsert.u8(OP_UPSERT_PROVIDER);
    upsert.u32(1);
    upsert.string("user_1");
    upsert.string("旧名");
    upsert.string("DOT");
    upsert.string("");
    upsert.string("old");
    upsert.i32(853);
    upsert.string("user_1");
    upsert.string(" 新名 ");
    upsert.string("DOT");
    upsert.string("new.example:853");
    let bytes = unsafe { call(diting_dns_config_core_providers, &upsert.finish()) };
    let mut reader = body_of(&bytes);
    assert_eq!(reader.u32(), Some(1));
    assert_eq!(reader.string().as_deref(), Some("user_1"));
    assert_eq!(reader.string().as_deref(), Some("新名"));

    let mut join = Writer::new();
    join.u8(OP_JOIN_HOST_PORT);
    join.string("::1");
    join.i32(853);
    let bytes = unsafe { call(diting_dns_config_core_providers, &join.finish()) };
    assert_eq!(body_of(&bytes).string().as_deref(), Some("[::1]:853"));
}

#[test]
fn preset_ops_cover_derivation_values_and_server_cache() {
    let mut from_policy = Writer::new();
    from_policy.u8(OP_PRESET_FROM_POLICY);
    from_policy.string("follow_dns_ttl");
    from_policy.i32(3600);
    from_policy.bool(false);
    from_policy.i32(60);
    from_policy.bool(false);
    from_policy.i32(300);
    let bytes = unsafe { call(diting_dns_config_core_presets, &from_policy.finish()) };
    assert_eq!(body_of(&bytes).u8(), Some(0));

    let mut current = Writer::new();
    current.u8(OP_PRESET_CURRENT);
    current.opt_string(Some("high_hit_rate"));
    current.string("follow_dns_ttl");
    current.i32(3600);
    current.bool(false);
    current.i32(60);
    current.bool(false);
    current.i32(300);
    let bytes = unsafe { call(diting_dns_config_core_presets, &current.finish()) };
    assert_eq!(body_of(&bytes).u8(), Some(2));

    let mut values = Writer::new();
    values.u8(OP_PRESET_VALUES);
    values.u8(2);
    let bytes = unsafe { call(diting_dns_config_core_presets, &values.finish()) };
    let mut reader = body_of(&bytes);
    assert_eq!(reader.string().as_deref(), Some("limit_max_ttl"));
    assert_eq!(reader.i32(), Some(21600));
    assert_eq!(reader.i32(), Some(3600));
    assert_eq!(reader.bool(), Some(true));
    assert_eq!(reader.i32(), Some(120));
    assert_eq!(reader.bool(), Some(true));
    assert_eq!(reader.i32(), Some(900));

    let mut server = Writer::new();
    server.u8(OP_SERVER_CACHE);
    server.string("conservative");
    let bytes = unsafe { call(diting_dns_config_core_presets, &server.finish()) };
    let mut reader = body_of(&bytes);
    assert_eq!(reader.string().as_deref(), Some("follow_dns_ttl"));
    assert_eq!(reader.i32(), Some(3600));
    assert_eq!(reader.i32(), Some(3600));
    assert_eq!(reader.bool(), Some(false));
    assert_eq!(reader.i32(), Some(60));
    assert_eq!(reader.bool(), Some(false));
    assert_eq!(reader.i32(), Some(300));
    assert_eq!(reader.i32(), Some(15));

    let mut storage = Writer::new();
    storage.u8(OP_PRESET_STORAGE);
    storage.u8(1);
    let bytes = unsafe { call(diting_dns_config_core_presets, &storage.finish()) };
    assert_eq!(body_of(&bytes).string().as_deref(), Some("balanced"));
}

#[test]
fn upstream_ops_cover_parse_encode_validate_normalize_and_host_port() {
    let mut parse = Writer::new();
    parse.u8(OP_PARSE_UPSTREAMS);
    parse.opt_string(Some(
        r#"[{"id":"u","name":"U","address":"9.9.9.9","port":5353,"protocol":"DNS"}]"#,
    ));
    let bytes = unsafe { call(diting_dns_config_core_upstreams, &parse.finish()) };
    let mut reader = body_of(&bytes);
    assert_eq!(reader.u32(), Some(1));
    assert_eq!(reader.string().as_deref(), Some("u"));
    assert_eq!(reader.string().as_deref(), Some("U"));
    assert_eq!(reader.string().as_deref(), Some("DNS"));
    assert_eq!(reader.string().as_deref(), Some("9.9.9.9"));
    assert_eq!(reader.i32(), Some(5353));

    let mut encode = Writer::new();
    encode.u8(OP_ENCODE_UPSTREAMS);
    encode.u32(1);
    encode.string("custom_x");
    encode.string("X");
    encode.string("DOT");
    encode.string("dot.example");
    encode.i32(853);
    let bytes = unsafe { call(diting_dns_config_core_upstreams, &encode.finish()) };
    let json = body_of(&bytes).string().expect("json");
    assert_eq!(
        json,
        r#"[{"id":"custom_x","name":"X","protocol":"DOT","address":"dot.example","port":853}]"#
    );

    let mut validate = Writer::new();
    validate.u8(OP_VALIDATE_UPSTREAM);
    validate.string("x");
    validate.string("DOH");
    validate.string("dns.example.com");
    validate.i32(443);
    let bytes = unsafe { call(diting_dns_config_core_upstreams, &validate.finish()) };
    assert_eq!(
        body_of(&bytes).u8(),
        Some(upstreams::UpstreamInvalid::DohNeedsHttps as u8)
    );

    let mut ok = Writer::new();
    ok.u8(OP_VALIDATE_UPSTREAM);
    ok.string("x");
    ok.string("DOT");
    ok.string("dot.example.com");
    ok.i32(853);
    let bytes = unsafe { call(diting_dns_config_core_upstreams, &ok.finish()) };
    assert_eq!(body_of(&bytes).u8(), Some(upstreams::UPSTREAM_OK));

    let mut normalize = Writer::new();
    normalize.u8(OP_NORMALIZE_ADDRESS);
    normalize.string("DNS");
    normalize.string(" [2001:db8::1] ");
    let bytes = unsafe { call(diting_dns_config_core_upstreams, &normalize.finish()) };
    assert_eq!(body_of(&bytes).string().as_deref(), Some("2001:db8::1"));

    let mut host_port = Writer::new();
    host_port.u8(OP_SERVER_HOST_PORT);
    host_port.string("2001:db8::1");
    host_port.i32(53);
    let bytes = unsafe { call(diting_dns_config_core_upstreams, &host_port.finish()) };
    assert_eq!(
        body_of(&bytes).string().as_deref(),
        Some("[2001:db8::1]:53")
    );
}

#[test]
fn malformed_payloads_are_rejected() {
    assert_eq!(
        unsafe { call(diting_dns_config_core_tunnel, &[]) },
        None,
        "empty payload"
    );
    assert_eq!(
        unsafe { call(diting_dns_config_core_server, &[0]) },
        None,
        "missing settings"
    );
    assert_eq!(
        unsafe { call(diting_dns_config_core_providers, &[9]) },
        None,
        "unknown op"
    );
    assert_eq!(
        unsafe { call(diting_dns_config_core_presets, &[OP_PRESET_VALUES, 7]) },
        None,
        "unknown preset"
    );
    assert_eq!(
        unsafe { call(diting_dns_config_core_upstreams, &[OP_SERVER_HOST_PORT, 0]) },
        None,
        "truncated host"
    );
}
