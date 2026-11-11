//! C ABI for the `dart:ffi` caller, plus the fixed payload layouts.
//!
//! One entry per area, one call per user action: these are dialog-sized payloads, so the boundary
//! costs nothing measurable and the kernel never holds state between calls.
//!
//! Every output starts with `magic "DAG1" | abi`; the Dart loader refuses a library whose version
//! does not match what it was compiled against, and a payload that runs past its buffer.

use crate::api;
use crate::paste;
use crate::payload::{read_summary, write_summary};
use crate::prompt;
use crate::secret;
use crate::traffic::{self, DnsRow};
use crate::wire::{Reader, Writer};

/// Bumped whenever a payload layout or a semantic changes.
pub const ABI_VERSION: u32 = 1;

const MAGIC: u32 = u32::from_le_bytes(*b"DAG1");

fn header(writer: &mut Writer) {
    writer.u32(MAGIC);
    writer.u32(ABI_VERSION);
}

/// Hands `bytes` to the caller as a pointer/length pair; shrinking keeps the length enough to
/// rebuild the allocation in [`diting_agent_core_free`].
fn into_buffer(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (pointer, length)
}

/// # Safety
/// `out_len` must be writable; `bytes` is either `None` (rejected payload, reported as null) or a
/// finished buffer whose ownership moves to the caller.
unsafe fn respond(bytes: Option<Vec<u8>>, out_len: *mut usize) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    match bytes {
        Some(bytes) => {
            let (pointer, length) = into_buffer(bytes);
            *out_len = length;
            pointer
        }
        None => {
            *out_len = 0;
            std::ptr::null_mut()
        }
    }
}

/// # Safety
/// `text` must point to `len` readable bytes.
unsafe fn input_at<'a>(text: *const u8, len: usize) -> &'a [u8] {
    if text.is_null() || len == 0 {
        &[]
    } else {
        std::slice::from_raw_parts(text, len)
    }
}

/// Payload layout version; the Dart loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_agent_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill. `dart:ffi` has no allocator of its own;
/// release it with [`diting_agent_core_free`].
#[no_mangle]
pub extern "C" fn diting_agent_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// Releases a buffer returned by any entry point below, or by [`diting_agent_core_alloc`].
///
/// # Safety
/// `pointer`/`len` must be exactly what the matching call returned, released once.
#[no_mangle]
pub unsafe extern "C" fn diting_agent_core_free(pointer: *mut u8, len: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(pointer, len, len));
}

unsafe fn utf8_input<'a>(input: *const u8, len: usize) -> Option<&'a str> {
    std::str::from_utf8(input_at(input, len)).ok()
}

/// Clipboard recognition. Input is the raw paste (UTF-8, not a payload).
///
/// # Safety
/// `input` must point to `len` readable bytes and `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_agent_core_paste(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let Some(text) = utf8_input(input, len) else {
        return respond(None, out_len);
    };
    let parsed = paste::parse(text);
    let mut writer = Writer::new();
    header(&mut writer);
    writer.u8(parsed.kind as u8);
    writer.opt_string(parsed.base_url.as_deref());
    writer.opt_string(parsed.api_key.as_deref());
    writer.opt_string(parsed.model.as_deref());
    respond(Some(writer.finish()), out_len)
}

/// Key sealing and opening: payload is `op u8 (0 seal, 1 open) | string`.
///
/// # Safety
/// Same contract as [`diting_agent_core_paste`].
#[no_mangle]
pub unsafe extern "C" fn diting_agent_core_secret(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = Reader::new(input_at(input, len));
    let Some(op) = reader.u8() else {
        return respond(None, out_len);
    };
    let Some(text) = reader.string() else {
        return respond(None, out_len);
    };
    let value = if op == 0 {
        secret::seal(&text)
    } else {
        secret::open(&text)
    };
    let mut writer = Writer::new();
    header(&mut writer);
    writer.string(&value);
    respond(Some(writer.finish()), out_len)
}

/// Prompt builders: `op u8 (0 domain, 1 traffic) | <fields>`.
///
/// Domain fields: `string domain | string systemPrompt | opt string context`. Traffic fields:
/// `string systemPrompt | <summary block>`. Output: `string systemPrompt | string userPrompt`.
///
/// # Safety
/// Same contract as [`diting_agent_core_paste`].
#[no_mangle]
pub unsafe extern "C" fn diting_agent_core_prompt(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = Reader::new(input_at(input, len));
    let Some(op) = reader.u8() else {
        return respond(None, out_len);
    };
    let request = if op == 0 {
        let Some(domain) = reader.string() else {
            return respond(None, out_len);
        };
        let Some(system_prompt) = reader.string() else {
            return respond(None, out_len);
        };
        let Some(context) = reader.opt_string() else {
            return respond(None, out_len);
        };
        prompt::domain_request(&domain, &system_prompt, context.as_deref())
    } else {
        let Some(system_prompt) = reader.string() else {
            return respond(None, out_len);
        };
        let Some(summary) = read_summary(&mut reader) else {
            return respond(None, out_len);
        };
        prompt::traffic_request(&summary, &system_prompt)
    };
    let mut writer = Writer::new();
    header(&mut writer);
    writer.string(&request.system_prompt);
    writer.string(&request.user_prompt);
    respond(Some(writer.finish()), out_len)
}

/// Traffic summary: `op u8 (0 summarize, 1 render) | <fields>`.
///
/// Summarise: `opt string unavailableReason | u32 dnsCount | (string domain, string result,
/// u8 cached)* | u32 httpCount | string outcome*`. Render: `<summary block>`.
///
/// # Safety
/// Same contract as [`diting_agent_core_paste`].
#[no_mangle]
pub unsafe extern "C" fn diting_agent_core_summary(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = Reader::new(input_at(input, len));
    let Some(op) = reader.u8() else {
        return respond(None, out_len);
    };
    let mut writer = Writer::new();
    header(&mut writer);
    if op == 0 {
        let Some(unavailable) = reader.opt_string() else {
            return respond(None, out_len);
        };
        let Some(dns_count) = reader.u32() else {
            return respond(None, out_len);
        };
        let mut dns = Vec::with_capacity(dns_count.min(4096) as usize);
        for _ in 0..dns_count {
            let Some(domain) = reader.string() else {
                return respond(None, out_len);
            };
            let Some(result) = reader.string() else {
                return respond(None, out_len);
            };
            let Some(cached) = reader.u8() else {
                return respond(None, out_len);
            };
            dns.push(DnsRow {
                domain,
                result,
                cached: cached != 0,
            });
        }
        let Some(http_count) = reader.u32() else {
            return respond(None, out_len);
        };
        let mut http = Vec::with_capacity(http_count.min(4096) as usize);
        for _ in 0..http_count {
            let Some(outcome) = reader.string() else {
                return respond(None, out_len);
            };
            http.push(outcome);
        }
        let summary = traffic::summarize(&dns, &http, unavailable);
        write_summary(&mut writer, &summary);
    } else {
        let Some(summary) = read_summary(&mut reader) else {
            return respond(None, out_len);
        };
        writer.string(&summary.render());
    }
    respond(Some(writer.finish()), out_len)
}

/// One error kind precedes the fields of a failed result.
fn write_endpoint(writer: &mut Writer, endpoint: Result<String, api::EndpointError>) {
    match endpoint {
        Ok(value) => {
            writer.u8(1);
            writer.string(&value);
        }
        Err(error) => writer.u8(error as u8),
    }
}

/// Protocol layer: `op u8 | <fields>`.
///
/// * `0`/`1` chat and models endpoint: `string baseUrl` -> `u8 ok | string`.
/// * `2` request body: `string model | f64 temperature | u32 count | (string role, string
///   content)*` -> `string json`.
/// * `3` chat reply: `string body | string fallbackModel` -> `u8 kind | (string content, string
///   model, u32 prompt, u32 completion, u32 total)` when the kind is `0`.
/// * `4` model list: `string body` -> `u8 kind | (u32 count | string*)` when the kind is `0`.
/// * `5` status hint: `u32 status | string body` -> `u8 kind | opt string detail`.
///
/// # Safety
/// Same contract as [`diting_agent_core_paste`].
#[no_mangle]
pub unsafe extern "C" fn diting_agent_core_api(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = Reader::new(input_at(input, len));
    let Some(op) = reader.u8() else {
        return respond(None, out_len);
    };
    let mut writer = Writer::new();
    header(&mut writer);
    match op {
        0 | 1 => {
            let Some(base_url) = reader.string() else {
                return respond(None, out_len);
            };
            let endpoint = if op == 0 {
                api::chat_endpoint(&base_url)
            } else {
                api::models_endpoint(&base_url)
            };
            write_endpoint(&mut writer, endpoint);
        }
        2 => {
            let Some(model) = reader.string() else {
                return respond(None, out_len);
            };
            let Some(temperature) = reader.f64() else {
                return respond(None, out_len);
            };
            let Some(count) = reader.u32() else {
                return respond(None, out_len);
            };
            let mut messages = Vec::with_capacity(count.min(64) as usize);
            for _ in 0..count {
                let Some(role) = reader.string() else {
                    return respond(None, out_len);
                };
                let Some(content) = reader.string() else {
                    return respond(None, out_len);
                };
                messages.push((role, content));
            }
            writer.string(&api::chat_body(&model, &messages, temperature));
        }
        3 => {
            let Some(body) = reader.string() else {
                return respond(None, out_len);
            };
            let Some(fallback_model) = reader.string() else {
                return respond(None, out_len);
            };
            match api::parse_chat(&body, &fallback_model) {
                Ok(reply) => {
                    writer.u8(0);
                    writer.string(&reply.content);
                    writer.string(&reply.model);
                    writer.u32(reply.prompt_tokens);
                    writer.u32(reply.completion_tokens);
                    writer.u32(reply.total_tokens);
                }
                Err(error) => writer.u8(error as u8),
            }
        }
        4 => {
            let Some(body) = reader.string() else {
                return respond(None, out_len);
            };
            match api::parse_models(&body) {
                Ok(models) => {
                    writer.u8(0);
                    writer.u32(models.len() as u32);
                    for model in &models {
                        writer.string(model);
                    }
                }
                Err(error) => writer.u8(error as u8),
            }
        }
        5 => {
            let Some(status) = reader.u32() else {
                return respond(None, out_len);
            };
            let Some(body) = reader.string() else {
                return respond(None, out_len);
            };
            let (kind, detail) = api::describe_status(status.min(u16::MAX as u32) as u16, &body);
            writer.u8(kind as u8);
            writer.opt_string(detail.as_deref());
        }
        _ => return respond(None, out_len),
    }
    respond(Some(writer.finish()), out_len)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::StatusKind;
    use crate::paste::PasteKind;

    /// Calls one entry the way Dart does and returns the bytes (or `None` for a rejected payload).
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
        diting_agent_core_free(pointer, out_len);
        Some(bytes)
    }

    fn body_of(bytes: &Option<Vec<u8>>) -> Reader<'_> {
        let bytes = bytes.as_ref().expect("payload");
        let mut reader = Reader::new(bytes);
        assert_eq!(reader.u32(), Some(MAGIC));
        assert_eq!(reader.u32(), Some(ABI_VERSION));
        reader
    }

    #[test]
    fn paste_entry_round_trips() {
        let payload = b"https://api.test/v1, sk-abcdefghijklmnop";
        let bytes = unsafe { call(diting_agent_core_paste, payload) };
        let mut reader = body_of(&bytes);
        assert_eq!(reader.u8(), Some(PasteKind::Both as u8));
        assert_eq!(
            reader.opt_string(),
            Some(Some("https://api.test/v1".to_string()))
        );
        assert_eq!(
            reader.opt_string(),
            Some(Some("sk-abcdefghijklmnop".to_string()))
        );
        assert_eq!(reader.opt_string(), Some(None));
    }

    #[test]
    fn secret_entry_seals_and_opens() {
        let mut writer = Writer::new();
        writer.u8(0);
        writer.string("sk-abc");
        let sealed = unsafe { call(diting_agent_core_secret, &writer.finish()) };
        let mut reader = body_of(&sealed);
        let sealed = reader.string().expect("sealed");

        let mut writer = Writer::new();
        writer.u8(1);
        writer.string(&sealed);
        let opened = unsafe { call(diting_agent_core_secret, &writer.finish()) };
        assert_eq!(body_of(&opened).string().as_deref(), Some("sk-abc"));
    }

    #[test]
    fn summary_entry_aggregates_then_renders() {
        let mut writer = Writer::new();
        writer.u8(0);
        writer.opt_string(None);
        writer.u32(2);
        writer.string("a.test");
        writer.string("PASSED");
        writer.u8(0);
        writer.string("a.test");
        writer.string("BLOCKED");
        writer.u8(1);
        writer.u32(1);
        writer.string("blocked");
        let summary = unsafe { call(diting_agent_core_summary, &writer.finish()) };
        let mut reader = body_of(&summary);
        assert_eq!(reader.u32(), Some(2));
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.u32(), Some(0));
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.u32(), Some(0));
        assert_eq!(reader.opt_string(), Some(None));
        assert_eq!(reader.u32(), Some(1));
        assert_eq!(reader.string().as_deref(), Some("a.test"));
        assert_eq!(reader.u32(), Some(2));

        // Round trip into the render op.
        let mut render = Writer::new();
        render.u8(1);
        write_summary(
            &mut render,
            &traffic::summarize(
                &[DnsRow {
                    domain: "a.test".to_string(),
                    result: "PASSED".to_string(),
                    cached: false,
                }],
                &[],
                None,
            ),
        );
        let rendered = unsafe { call(diting_agent_core_summary, &render.finish()) };
        let text = body_of(&rendered).string().expect("rendered");
        assert!(text.starts_with("【近期 DNS 监控统计】"));
    }

    #[test]
    fn prompt_entry_builds_both_modes() {
        let mut domain = Writer::new();
        domain.u8(0);
        domain.string("example.com");
        domain.string("sys");
        domain.opt_string(Some("log line"));
        let built = unsafe { call(diting_agent_core_prompt, &domain.finish()) };
        let mut reader = body_of(&built);
        assert_eq!(reader.string().as_deref(), Some("sys"));
        let user = reader.string().expect("prompt");
        assert!(user.contains("目标域名：example.com"));
        assert!(user.contains("log line"));

        let mut traffic = Writer::new();
        traffic.u8(1);
        traffic.string("");
        write_summary(&mut traffic, &traffic::summarize(&[], &[], None));
        let built = unsafe { call(diting_agent_core_prompt, &traffic.finish()) };
        let mut reader = body_of(&built);
        assert_eq!(
            reader.string().as_deref(),
            Some(prompt::DEFAULT_TRAFFIC_SYSTEM_PROMPT)
        );
        assert!(reader.string().expect("prompt").contains("样本不足"));
    }

    #[test]
    fn api_entry_covers_endpoints_chat_and_models() {
        let mut writer = Writer::new();
        writer.u8(0);
        writer.string("https://api.deepseek.com");
        let bytes = unsafe { call(diting_agent_core_api, &writer.finish()) };
        let mut reader = body_of(&bytes);
        assert_eq!(reader.u8(), Some(1));
        assert_eq!(
            reader.string().as_deref(),
            Some("https://api.deepseek.com/v1/chat/completions")
        );

        let mut writer = Writer::new();
        writer.u8(1);
        writer.string("  ");
        let bytes = unsafe { call(diting_agent_core_api, &writer.finish()) };
        assert_eq!(body_of(&bytes).u8(), Some(api::EndpointError::Empty as u8));

        let mut writer = Writer::new();
        writer.u8(3);
        writer.string(r#"{"choices":[{"message":{"content":" hi "}}]}"#);
        writer.string("m");
        let bytes = unsafe { call(diting_agent_core_api, &writer.finish()) };
        let mut reader = body_of(&bytes);
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.string().as_deref(), Some("hi"));
        assert_eq!(reader.string().as_deref(), Some("m"));

        let mut writer = Writer::new();
        writer.u8(4);
        writer.string(r#"{"data":[{"id":"b"},{"id":"a"}]}"#);
        let bytes = unsafe { call(diting_agent_core_api, &writer.finish()) };
        let mut reader = body_of(&bytes);
        assert_eq!(reader.u8(), Some(0));
        assert_eq!(reader.u32(), Some(2));
        assert_eq!(reader.string().as_deref(), Some("a"));
        assert_eq!(reader.string().as_deref(), Some("b"));

        let mut writer = Writer::new();
        writer.u8(5);
        writer.u32(401);
        writer.string(r#"{"error":{"message":"Invalid token"}}"#);
        let bytes = unsafe { call(diting_agent_core_api, &writer.finish()) };
        let mut reader = body_of(&bytes);
        assert_eq!(reader.u8(), Some(StatusKind::BadKey as u8));
        assert_eq!(reader.opt_string(), Some(Some("Invalid token".to_string())));
    }

    #[test]
    fn malformed_payloads_are_rejected() {
        assert_eq!(unsafe { call(diting_agent_core_secret, &[]) }, None);
        assert_eq!(unsafe { call(diting_agent_core_prompt, &[0]) }, None);
        assert_eq!(unsafe { call(diting_agent_core_api, &[9]) }, None);
        let mut writer = Writer::new();
        writer.u8(0);
        writer.u32(3);
        assert_eq!(
            unsafe { call(diting_agent_core_summary, &writer.finish()) },
            None
        );
    }
}
