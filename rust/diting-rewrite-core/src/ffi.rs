use std::slice;

use crate::action::Action;
use crate::engine::Engine;
use crate::payload::{
    decode_action, decode_action_text, decode_engine_config, decode_request, encode_action,
    encode_action_key, encode_engine_build, encode_engine_domains, encode_engine_lookup,
    encode_engine_reverse, encode_reply, encode_type_names,
};
use crate::record;

pub const ABI_VERSION: u32 = 3;

const STATUS_OK: u32 = 0;
const STATUS_REJECTED: u32 = 1;
const STATUS_BAD_ARGS: u32 = 2;

#[no_mangle]
pub extern "C" fn diting_rewrite_abi_version() -> u32 {
    ABI_VERSION
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_build_record(
    input: *const u8,
    input_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    drive(input, input_len, payload_out, payload_len, build_reply)
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_parse_action(
    input: *const u8,
    input_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    drive(
        input,
        input_len,
        payload_out,
        payload_len,
        parse_action_reply,
    )
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_action_key(
    input: *const u8,
    input_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    drive(input, input_len, payload_out, payload_len, action_key_reply)
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_record_types(
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    write_payload(
        encode_type_names(record::type_names()),
        payload_out,
        payload_len,
    );
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_free_bytes(pointer: *mut u8, length: usize) {
    if !pointer.is_null() && length > 0 {
        drop(Vec::from_raw_parts(pointer, length, length));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_build(
    input: *const u8,
    input_len: usize,
    handle_out: *mut *mut Engine,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle_out.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if input.is_null() && input_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let data = if input_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input, input_len)
    };
    match decode_engine_config(data) {
        Ok(config) => {
            let (engine, warnings) = Engine::build(&config);
            *handle_out = Box::into_raw(Box::new(engine));
            write_payload(encode_engine_build(&warnings), payload_out, payload_len);
            STATUS_OK
        }
        Err(error) => {
            write_payload(error.0.into_bytes(), payload_out, payload_len);
            STATUS_REJECTED
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_free(handle: *mut Engine) {
    if !handle.is_null() {
        drop(Box::from_raw(handle));
    }
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_lookup(
    handle: *mut Engine,
    name: *const u8,
    name_len: usize,
    qtype: u16,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if name.is_null() && name_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let bytes = if name_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(name, name_len)
    };
    let Ok(text) = std::str::from_utf8(bytes) else {
        write_payload(
            "query name is not valid UTF-8".as_bytes().to_vec(),
            payload_out,
            payload_len,
        );
        return STATUS_REJECTED;
    };
    let result = (*handle).lookup(text, qtype);
    write_payload(encode_engine_lookup(&result), payload_out, payload_len);
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_ptr_lookup(
    handle: *mut Engine,
    ip: *const u8,
    ip_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if ip.is_null() && ip_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let bytes = if ip_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(ip, ip_len)
    };
    write_payload(
        encode_engine_domains(&(*handle).lookup_ptr(bytes)),
        payload_out,
        payload_len,
    );
    STATUS_OK
}

#[no_mangle]
pub unsafe extern "C" fn diting_rewrite_engine_reverse_lookup(
    handle: *mut Engine,
    ip: *const u8,
    ip_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
) -> u32 {
    if handle.is_null() || payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if ip.is_null() && ip_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let bytes = if ip_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(ip, ip_len)
    };
    let domain = (*handle).lookup_reverse(bytes);
    let reply = if domain.is_empty() {
        encode_engine_reverse(None)
    } else {
        encode_engine_reverse(Some(&domain))
    };
    write_payload(reply, payload_out, payload_len);
    STATUS_OK
}

fn build_reply(data: &[u8]) -> Result<Vec<u8>, String> {
    let request = decode_request(data).map_err(|error| error.0)?;
    let record = record::build(
        &request.owner,
        request.qtype,
        &request.type_name,
        &request.value,
        request.ttl,
    )?;
    Ok(encode_reply(record.as_ref()))
}

fn parse_action_reply(data: &[u8]) -> Result<Vec<u8>, String> {
    let text = decode_action_text(data).map_err(|error| error.0)?;
    let action = Action::parse(&text)?;
    Ok(encode_action(&action))
}

fn action_key_reply(data: &[u8]) -> Result<Vec<u8>, String> {
    let action = decode_action(data).map_err(|error| error.0)?;
    Ok(encode_action_key(&action.key()))
}

unsafe fn drive<F>(
    input: *const u8,
    input_len: usize,
    payload_out: *mut *mut u8,
    payload_len: *mut usize,
    handler: F,
) -> u32
where
    F: FnOnce(&[u8]) -> Result<Vec<u8>, String>,
{
    if payload_out.is_null() || payload_len.is_null() {
        return STATUS_BAD_ARGS;
    }
    if input.is_null() && input_len > 0 {
        return STATUS_BAD_ARGS;
    }
    let data = if input_len == 0 {
        &[][..]
    } else {
        slice::from_raw_parts(input, input_len)
    };
    match handler(data) {
        Ok(payload) => {
            write_payload(payload, payload_out, payload_len);
            STATUS_OK
        }
        Err(message) => {
            write_payload(message.into_bytes(), payload_out, payload_len);
            STATUS_REJECTED
        }
    }
}

unsafe fn write_payload(bytes: Vec<u8>, out: *mut *mut u8, out_len: *mut usize) {
    let mut boxed = bytes.into_boxed_slice();
    *out_len = boxed.len();
    *out = boxed.as_mut_ptr();
    std::mem::forget(boxed);
}

#[cfg(test)]
mod tests;
