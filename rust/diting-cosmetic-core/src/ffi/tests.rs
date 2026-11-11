//! Tests through the C ABI, the way `android/engine/mitm_cosmetic_native.go` drives it.

use super::*;
use crate::inject::Upstream;
use crate::payload::decode_text;

/// Reads the payload `diting_cosmetic_link_tag` returned and frees it, as Go must.
unsafe fn take_link_tag(host: &str, asset_host: &str) -> String {
    let mut pointer: *mut u8 = std::ptr::null_mut();
    let mut length = 0usize;
    let status = diting_cosmetic_link_tag(
        host.as_ptr(),
        host.len(),
        asset_host.as_ptr(),
        asset_host.len(),
        &mut pointer,
        &mut length,
    );
    assert_eq!(status, STATUS_OK);
    let payload = slice::from_raw_parts(pointer, length).to_vec();
    diting_cosmetic_free_bytes(pointer, length);
    decode_text(&payload).expect("payload decodes")
}

unsafe fn open_reader(link_tag: &str) -> *mut Injector {
    let payload = crate::payload::encode_text(link_tag.as_bytes());
    let mut handle: *mut Injector = std::ptr::null_mut();
    assert_eq!(
        diting_cosmetic_new(payload.as_ptr(), payload.len(), &mut handle),
        STATUS_OK
    );
    assert!(!handle.is_null());
    handle
}

/// One `Read`: the queued bytes first, then the upstream chunk, exactly like the Go wrapper.
unsafe fn read(
    handle: *mut Injector,
    buffer: &mut [u8],
    upstream_chunk: &[u8],
    upstream: Upstream,
) -> (usize, bool) {
    let queued = diting_cosmetic_pending(handle, buffer.as_mut_ptr(), buffer.len());
    if queued > 0 {
        return (queued as usize, false);
    }
    let n = upstream_chunk.len().min(buffer.len());
    buffer[..n].copy_from_slice(&upstream_chunk[..n]);
    let mut out_len = 0u32;
    let mut keep_error = 0u8;
    assert_eq!(
        diting_cosmetic_process(
            handle,
            buffer.as_mut_ptr(),
            buffer.len(),
            n,
            upstream.flags(),
            &mut out_len,
            &mut keep_error,
        ),
        STATUS_OK
    );
    (out_len as usize, keep_error == 1)
}

#[test]
fn abi_version_is_pinned() {
    assert_eq!(diting_cosmetic_abi_version(), ABI_VERSION);
}

/// Reads the payload `diting_cosmetic_normalize_host` returned and frees it, as Go must.
unsafe fn take_normalized(host: &str) -> String {
    let mut pointer: *mut u8 = std::ptr::null_mut();
    let mut length = 0usize;
    let status =
        diting_cosmetic_normalize_host(host.as_ptr(), host.len(), &mut pointer, &mut length);
    assert_eq!(status, STATUS_OK);
    let payload = slice::from_raw_parts(pointer, length).to_vec();
    diting_cosmetic_free_bytes(pointer, length);
    decode_text(&payload).expect("payload decodes")
}

#[test]
fn normalize_host_arrives_as_a_layout_payload() {
    assert_eq!(
        unsafe { take_normalized(" Ads.Example.com:443 ") },
        "ads.example.com"
    );
    assert_eq!(unsafe { take_normalized("[::1]:443") }, "[::1]");
    assert_eq!(unsafe { take_normalized(".") }, "");
}

#[test]
fn link_tag_arrives_as_a_layout_payload() {
    let tag = unsafe { take_link_tag("Ads.Example.com:443", "local.pwhs.app") };
    assert_eq!(
        tag,
        r#"<link rel="stylesheet" href="https://local.pwhs.app/cosmetic.css?h=ads.example.com">"#
    );
}

#[test]
fn a_null_handle_reports_no_pending_bytes_and_refuses_to_process() {
    let mut buffer = [0u8; 8];
    assert_eq!(
        unsafe { diting_cosmetic_pending(std::ptr::null_mut(), buffer.as_mut_ptr(), buffer.len()) },
        0
    );
    let mut out_len = 0u32;
    let mut keep_error = 0u8;
    assert_eq!(
        unsafe {
            diting_cosmetic_process(
                std::ptr::null_mut(),
                buffer.as_mut_ptr(),
                buffer.len(),
                0,
                Upstream::EOF.flags(),
                &mut out_len,
                &mut keep_error,
            )
        },
        STATUS_BAD_ARGUMENT
    );
}

#[test]
fn a_drifted_link_payload_is_rejected() {
    let mut payload = crate::payload::encode_text(b"[LINK]");
    payload[0] = crate::payload::LAYOUT_VERSION + 1;
    let mut handle: *mut Injector = std::ptr::null_mut();
    assert_eq!(
        unsafe { diting_cosmetic_new(payload.as_ptr(), payload.len(), &mut handle) },
        STATUS_BAD_PAYLOAD
    );
    assert!(handle.is_null());
}

#[test]
fn a_reader_splices_the_tag_over_two_reads() {
    let handle = unsafe { open_reader("[LINK]") };
    let mut buffer = [0u8; 64];
    let mut out = Vec::new();

    // `<he` is a prefix of `<head`, so the tail waits for the next read.
    let (n, keep) = unsafe { read(handle, &mut buffer, b"<html><he", Upstream::NONE) };
    out.extend_from_slice(&buffer[..n]);
    assert!(keep);
    assert_eq!(String::from_utf8_lossy(&out), "<html>");

    let (n, keep) = unsafe { read(handle, &mut buffer, b"ad><body>", Upstream::EOF) };
    out.extend_from_slice(&buffer[..n]);
    // Everything fit, so the EOF travels with the last chunk.
    assert!(keep);
    unsafe { diting_cosmetic_free(handle) };

    assert_eq!(String::from_utf8_lossy(&out), "<html><head>[LINK]<body>");
}

#[test]
fn a_queued_tag_clears_before_the_eof_travels() {
    let handle = unsafe { open_reader("0123456789") };
    // `<head>` + the ten-byte tag does not fit, so the tail is queued and the EOF waits for it.
    let mut buffer = [0u8; 8];
    let mut out = Vec::new();
    let mut reads = Vec::new();

    let (n, keep) = unsafe { read(handle, &mut buffer, b"<head>", Upstream::EOF) };
    out.extend_from_slice(&buffer[..n]);
    reads.push((n, keep));
    assert!(!keep, "the queue drains before the EOF travels");

    // The Go loop keeps calling Read until an error comes back; the queue empties first.
    for _ in 0..8 {
        let (n, keep) = unsafe { read(handle, &mut buffer, b"", Upstream::EOF) };
        out.extend_from_slice(&buffer[..n]);
        reads.push((n, keep));
        if n == 0 {
            break;
        }
    }
    unsafe { diting_cosmetic_free(handle) };

    assert_eq!(String::from_utf8_lossy(&out), "<head>0123456789");
    assert_eq!(reads, vec![(8, false), (8, false), (0, true)]);
}

// --- the local asset server and the rule set ---------------------------------

use crate::payload::{decode_response, decode_text_list, encode_rules};
use crate::rules::{DomainRules, RuleSet, Rules};

unsafe fn open_rules(rules: &RuleSet) -> *mut RuleSet {
    let payload = encode_rules(rules);
    let mut handle: *mut RuleSet = std::ptr::null_mut();
    assert_eq!(
        diting_cosmetic_rules_new(payload.as_ptr(), payload.len(), &mut handle),
        STATUS_OK
    );
    assert!(!handle.is_null());
    handle
}

unsafe fn take_payload(call: impl FnOnce(*mut *mut u8, *mut usize) -> u32) -> Vec<u8> {
    let mut pointer: *mut u8 = std::ptr::null_mut();
    let mut length = 0usize;
    assert_eq!(call(&mut pointer, &mut length), STATUS_OK);
    let payload = slice::from_raw_parts(pointer, length).to_vec();
    diting_cosmetic_free_bytes(pointer, length);
    payload
}

fn fixture_rules() -> RuleSet {
    let mut domains = std::collections::HashMap::new();
    domains.insert(
        "example.com".to_string(),
        DomainRules {
            hide: vec![".banner-ad".to_string()],
            exception: vec![".site-banner".to_string()],
        },
    );
    RuleSet::Loaded(Rules {
        global_hide: vec![".generic-ad".to_string()],
        global_exception: Vec::new(),
        domains,
    })
}

#[test]
fn the_rule_set_handle_renders_the_stylesheet() {
    let handle = unsafe { open_rules(&fixture_rules()) };
    let css = decode_text(&unsafe {
        take_payload(|out, out_len| {
            diting_cosmetic_rules_render(handle, b"www.example.com".as_ptr(), 15, out, out_len)
        })
    })
    .unwrap();
    unsafe { diting_cosmetic_rules_free(handle) };

    assert_eq!(
        css,
        ".banner-ad { display: none !important; }\n\
         .generic-ad { display: none !important; }\n\
         .site-banner { display: revert !important; }\n"
    );
}

#[test]
fn a_null_rule_handle_renders_the_empty_sentinel() {
    let css = decode_text(&unsafe {
        take_payload(|out, out_len| {
            diting_cosmetic_rules_render(
                std::ptr::null(),
                b"example.com".as_ptr(),
                11,
                out,
                out_len,
            )
        })
    })
    .unwrap();
    assert_eq!(css, crate::rules::NO_RULES);
}

#[test]
fn a_drifted_rules_payload_is_rejected() {
    let mut payload = encode_rules(&RuleSet::Empty);
    payload[0] = crate::payload::LAYOUT_VERSION + 1;
    let mut handle: *mut RuleSet = std::ptr::null_mut();
    assert_eq!(
        unsafe { diting_cosmetic_rules_new(payload.as_ptr(), payload.len(), &mut handle) },
        STATUS_BAD_PAYLOAD
    );
    assert!(handle.is_null());
}

#[test]
fn host_suffixes_arrive_as_a_text_list() {
    let payload = unsafe {
        take_payload(|out, out_len| {
            diting_cosmetic_host_suffixes(b"Ads.Example.com".as_ptr(), 15, out, out_len)
        })
    };
    assert_eq!(
        decode_text_list(&payload).unwrap(),
        vec!["ads.example.com", "example.com", "com"]
    );
}

#[test]
fn the_asset_host_match_matches_the_flow_handler() {
    assert_eq!(
        unsafe { diting_cosmetic_is_asset_host(b"local.pwhs.app".as_ptr(), 14) },
        1
    );
    assert_eq!(
        unsafe { diting_cosmetic_is_asset_host(b"LOCAL.pwhs.app:443".as_ptr(), 19) },
        1
    );
    assert_eq!(
        unsafe { diting_cosmetic_is_asset_host(b"[::1]:443".as_ptr(), 9) },
        0
    );
    assert_eq!(
        unsafe { diting_cosmetic_is_asset_host(std::ptr::null(), 0) },
        0
    );
}

#[test]
fn the_local_response_carries_the_route_and_headers() {
    let handle = unsafe { open_rules(&fixture_rules()) };
    let css = unsafe {
        take_payload(|out, out_len| {
            diting_cosmetic_local_response(
                handle,
                b"/cosmetic.css".as_ptr(),
                13,
                b"www.example.com".as_ptr(),
                15,
                4096,
                out,
                out_len,
            )
        })
    };
    let response = decode_response(&css).unwrap();
    assert_eq!(response.status, 200);
    assert_eq!(response.content_type, "text/css; charset=utf-8");
    assert!(response.body.contains(".banner-ad"));
    assert!(response
        .headers
        .iter()
        .any(|(name, value)| name == "Vary" && value == "X-DITING-Host"));

    let health = unsafe {
        take_payload(|out, out_len| {
            diting_cosmetic_local_response(
                std::ptr::null(),
                b"/health".as_ptr(),
                7,
                std::ptr::null(),
                0,
                4096,
                out,
                out_len,
            )
        })
    };
    let health = decode_response(&health).unwrap();
    assert_eq!(health.body, r#"{"status":"ok","css_bytes":4096}"#);

    let missing = unsafe {
        take_payload(|out, out_len| {
            diting_cosmetic_local_response(
                handle,
                b"/nope".as_ptr(),
                5,
                std::ptr::null(),
                0,
                0,
                out,
                out_len,
            )
        })
    };
    let missing = decode_response(&missing).unwrap();
    assert_eq!(missing.status, 404);
    assert_eq!(missing.body, "Not Found");
    unsafe { diting_cosmetic_rules_free(handle) };
}
