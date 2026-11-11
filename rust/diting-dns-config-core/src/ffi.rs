//! C ABI for the `dart:ffi` caller.
//!
//! Three shapes: the two documents (one call each), and three record-list entries whose first byte
//! selects the operation. Every output starts with `magic "DDC1" | abi`; the Dart loader refuses a
//! library whose version does not match what it was compiled against.

use crate::bootstrap::{self, BootstrapRow};
use crate::document::{self, BootstrapEntry};
use crate::input;
use crate::presets::{self, CachePolicy, CachePreset};
use crate::protocol::{self, Protocol};
use crate::providers::{self, Provider};
use crate::upstreams::{self, ServerUpstream};
use crate::wire::{Reader, Writer};

/// Bumped whenever a payload layout or a document field changes.
pub const ABI_VERSION: u32 = 2;

const MAGIC: u32 = u32::from_le_bytes(*b"DDC1");
const OP_SPLIT_ADDRESS: u8 = 0;
const OP_PARSE_PROVIDERS: u8 = 1;
const OP_ENCODE_PROVIDERS: u8 = 2;
const OP_UPSERT_PROVIDER: u8 = 3;
const OP_JOIN_HOST_PORT: u8 = 4;
const OP_PARSE_BOOTSTRAP: u8 = 5;
const OP_ENCODE_BOOTSTRAP: u8 = 6;
const OP_PRESET_FROM_POLICY: u8 = 0;
const OP_PRESET_CURRENT: u8 = 1;
const OP_PRESET_VALUES: u8 = 2;
const OP_SERVER_CACHE: u8 = 3;
const OP_PRESET_STORAGE: u8 = 4;
const OP_PARSE_UPSTREAMS: u8 = 0;
const OP_ENCODE_UPSTREAMS: u8 = 1;
const OP_VALIDATE_UPSTREAM: u8 = 2;
const OP_NORMALIZE_ADDRESS: u8 = 3;
const OP_SERVER_HOST_PORT: u8 = 4;

fn header(writer: &mut Writer) {
    writer.u32(MAGIC);
    writer.u32(ABI_VERSION);
}

fn into_buffer(bytes: Vec<u8>) -> (*mut u8, usize) {
    let mut boxed = bytes.into_boxed_slice();
    let length = boxed.len();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    (pointer, length)
}

/// # Safety
/// `out_len` must be writable; `bytes` is `None` for a rejected payload.
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
/// `input` must point to `len` readable bytes.
unsafe fn reader_at<'a>(input: *const u8, len: usize) -> Reader<'a> {
    if input.is_null() || len == 0 {
        Reader::new(&[])
    } else {
        Reader::new(std::slice::from_raw_parts(input, len))
    }
}

fn write_providers(writer: &mut Writer, providers: &[Provider]) {
    writer.u32(providers.len() as u32);
    for provider in providers {
        writer.string(&provider.id);
        writer.string(&provider.name);
        writer.string(protocol::storage_value(provider.protocol));
        writer.string(&provider.url);
        writer.string(&provider.host);
        writer.i32(provider.port);
    }
}

fn write_bootstrap(writer: &mut Writer, entries: &[BootstrapEntry]) {
    writer.u32(entries.len() as u32);
    for entry in entries {
        writer.string(&entry.id);
        writer.string(&entry.name);
        writer.string(&entry.ip);
    }
}

fn write_bootstrap_rows(writer: &mut Writer, rows: &[BootstrapRow]) {
    writer.u32(rows.len() as u32);
    for row in rows {
        writer.string(&row.id);
        writer.string(&row.name);
        writer.string(&row.ip);
        writer.bool(row.enabled);
    }
}

fn write_upstreams(writer: &mut Writer, upstreams: &[ServerUpstream]) {
    writer.u32(upstreams.len() as u32);
    for upstream in upstreams {
        writer.string(&upstream.id);
        writer.string(&upstream.name);
        writer.string(protocol::storage_value(upstream.protocol));
        writer.string(&upstream.address);
        writer.i32(upstream.port);
    }
}

fn write_cache_values(writer: &mut Writer, values: presets::CacheValues) {
    writer.string(values.mode);
    writer.i32(values.max_ttl_seconds);
    writer.i32(values.fixed_ttl_seconds);
    writer.bool(values.min_ttl_enabled);
    writer.i32(values.min_ttl_seconds);
    writer.bool(values.stale_fallback_enabled);
    writer.i32(values.stale_fallback_seconds);
}

fn read_protocol(reader: &mut Reader<'_>) -> Option<Protocol> {
    let storage = reader.string()?;
    Some(protocol::from_storage(&storage).unwrap_or(Protocol::Plain))
}

fn read_cache_policy(reader: &mut Reader<'_>) -> Option<CachePolicy> {
    Some(CachePolicy {
        mode: reader.string()?,
        max_ttl_seconds: reader.i32()?,
        min_ttl_enabled: reader.bool()?,
        min_ttl_seconds: reader.i32()?,
        stale_fallback_enabled: reader.bool()?,
        stale_fallback_seconds: reader.i32()?,
    })
}

/// Payload layout version; the Dart loader compares it against its own constant.
#[no_mangle]
pub extern "C" fn diting_dns_config_core_abi_version() -> u32 {
    ABI_VERSION
}

/// Allocates `size` zeroed bytes for the caller to fill. Release it with
/// [`diting_dns_config_core_free`].
#[no_mangle]
pub extern "C" fn diting_dns_config_core_alloc(size: usize) -> *mut u8 {
    if size == 0 {
        return std::ptr::null_mut();
    }
    let mut boxed = vec![0u8; size].into_boxed_slice();
    let pointer = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    pointer
}

/// Releases a buffer returned by any entry point below, or by
/// [`diting_dns_config_core_alloc`].
///
/// # Safety
/// `pointer`/`len` must be exactly what the matching call returned, released once.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_config_core_free(pointer: *mut u8, len: usize) {
    if pointer.is_null() {
        return;
    }
    drop(Vec::from_raw_parts(pointer, len, len));
}

/// The tunnel's `ApplyDNSConfig` document plus the rows the UI shows.
///
/// Input: `flags | settings fields | preset providers | preset bootstrap`. Output:
/// `mode | document | picked providers | bootstrap entries`.
///
/// # Safety
/// `input` must point to `len` readable bytes and `out_len` must be writable.
#[no_mangle]
pub unsafe extern "C" fn diting_dns_config_core_tunnel(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = reader_at(input, len);
    let Some(settings) = input::tunnel_settings(&mut reader) else {
        return respond(None, out_len);
    };
    let Some(preset_providers) = input::read_providers(&mut reader) else {
        return respond(None, out_len);
    };
    let Some(preset_bootstrap) = input::read_bootstrap(&mut reader) else {
        return respond(None, out_len);
    };
    let config = document::build_tunnel(&settings, &preset_providers, &preset_bootstrap);
    let mut writer = Writer::new();
    header(&mut writer);
    writer.string(&config.mode);
    writer.string(&config.document);
    write_providers(&mut writer, &config.providers);
    write_bootstrap(&mut writer, &config.bootstrap);
    respond(Some(writer.finish()), out_len)
}

/// Server mode's `applyDnsConfig` document plus the upstreams it picked.
///
/// Output: `port | mode | document | picked upstreams`, in engine attempt order (one row for
/// `single`, the whole race list otherwise).
///
/// # Safety
/// Same contract as [`diting_dns_config_core_tunnel`].
#[no_mangle]
pub unsafe extern "C" fn diting_dns_config_core_server(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = reader_at(input, len);
    let Some(settings) = input::server_settings(&mut reader) else {
        return respond(None, out_len);
    };
    let Some(preset_upstreams) = input::read_upstreams(&mut reader) else {
        return respond(None, out_len);
    };
    let Some(config) = document::build_server(&settings, &preset_upstreams) else {
        return respond(None, out_len);
    };
    let mut writer = Writer::new();
    header(&mut writer);
    writer.i32(config.port);
    writer.string(&config.mode);
    writer.string(&config.document);
    write_upstreams(&mut writer, &config.providers);
    respond(Some(writer.finish()), out_len)
}

/// `user_providers_json` helpers: `op u8 | fields`.
///
/// * `0` split address: `protocol | address` -> `url | host | port`.
/// * `1` parse: `opt raw` -> records.
/// * `2` encode: records -> `json`.
/// * `3` upsert: `records | id | name | protocol | address` -> records.
/// * `4` join host and port: `host | port` -> `host:port`.
/// * `5` parse custom bootstrap rows: `opt raw` -> rows (`id | name | ip | enabled`).
/// * `6` encode custom bootstrap rows: rows -> `json`.
///
/// # Safety
/// Same contract as [`diting_dns_config_core_tunnel`].
#[no_mangle]
pub unsafe extern "C" fn diting_dns_config_core_providers(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = reader_at(input, len);
    let Some(op) = reader.u8() else {
        return respond(None, out_len);
    };
    let mut writer = Writer::new();
    header(&mut writer);
    match op {
        OP_SPLIT_ADDRESS => {
            let Some(protocol) = read_protocol(&mut reader) else {
                return respond(None, out_len);
            };
            let Some(address) = reader.string() else {
                return respond(None, out_len);
            };
            let (url, host, port) = providers::split_address(protocol, &address);
            writer.string(&url);
            writer.string(&host);
            writer.i32(port);
        }
        OP_PARSE_PROVIDERS => {
            let Some(raw) = reader.opt_string() else {
                return respond(None, out_len);
            };
            write_providers(
                &mut writer,
                &providers::parse_user_providers(raw.as_deref()),
            );
        }
        OP_ENCODE_PROVIDERS => {
            let Some(records) = input::read_providers(&mut reader) else {
                return respond(None, out_len);
            };
            writer.string(&providers::encode_user_providers(&records));
        }
        OP_UPSERT_PROVIDER => {
            let Some(records) = input::read_providers(&mut reader) else {
                return respond(None, out_len);
            };
            let Some(id) = reader.string() else {
                return respond(None, out_len);
            };
            let Some(name) = reader.string() else {
                return respond(None, out_len);
            };
            let Some(protocol) = read_protocol(&mut reader) else {
                return respond(None, out_len);
            };
            let Some(address) = reader.string() else {
                return respond(None, out_len);
            };
            let updated = providers::upsert_user_provider(&records, &id, &name, protocol, &address);
            write_providers(&mut writer, &updated);
        }
        OP_JOIN_HOST_PORT => {
            let (Some(host), Some(port)) = (reader.string(), reader.i32()) else {
                return respond(None, out_len);
            };
            writer.string(&protocol::join_host_port(&host, port));
        }
        OP_PARSE_BOOTSTRAP => {
            let Some(raw) = reader.opt_string() else {
                return respond(None, out_len);
            };
            write_bootstrap_rows(&mut writer, &bootstrap::parse_custom(raw.as_deref()));
        }
        OP_ENCODE_BOOTSTRAP => {
            let Some(rows) = input::read_bootstrap_rows(&mut reader) else {
                return respond(None, out_len);
            };
            writer.string(&bootstrap::encode_custom(&rows));
        }
        _ => return respond(None, out_len),
    }
    respond(Some(writer.finish()), out_len)
}

/// Cache presets: `op u8 | fields`.
///
/// * `0` derive from policy: `policy fields` -> preset index.
/// * `1` current preset: `opt preset | policy fields` -> preset index.
/// * `2` preset values: `index` -> the nine prefs values.
/// * `3` server-mode cache: `preset` -> values plus the negative TTL.
/// * `4` storage spelling: `index` -> `conservative` / `balanced` / `high_hit_rate`.
///
/// # Safety
/// Same contract as [`diting_dns_config_core_tunnel`].
#[no_mangle]
pub unsafe extern "C" fn diting_dns_config_core_presets(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = reader_at(input, len);
    let Some(op) = reader.u8() else {
        return respond(None, out_len);
    };
    let mut writer = Writer::new();
    header(&mut writer);
    match op {
        OP_PRESET_FROM_POLICY => {
            let Some(policy) = read_cache_policy(&mut reader) else {
                return respond(None, out_len);
            };
            writer.u8(presets::from_policy(&policy) as u8);
        }
        OP_PRESET_CURRENT => {
            let Some(raw) = reader.opt_string() else {
                return respond(None, out_len);
            };
            let Some(policy) = read_cache_policy(&mut reader) else {
                return respond(None, out_len);
            };
            writer.u8(presets::current(raw.as_deref(), &policy) as u8);
        }
        OP_PRESET_VALUES => {
            let Some(index) = reader.u8() else {
                return respond(None, out_len);
            };
            let Some(preset) = CachePreset::from_index(index) else {
                return respond(None, out_len);
            };
            write_cache_values(&mut writer, preset.values());
        }
        OP_SERVER_CACHE => {
            let Some(raw) = reader.string() else {
                return respond(None, out_len);
            };
            let (values, negative_ttl_seconds) = presets::server_cache_document(&raw);
            write_cache_values(&mut writer, values);
            writer.i32(negative_ttl_seconds);
        }
        OP_PRESET_STORAGE => {
            let Some(index) = reader.u8() else {
                return respond(None, out_len);
            };
            let Some(preset) = CachePreset::from_index(index) else {
                return respond(None, out_len);
            };
            writer.string(preset.storage_value());
        }
        _ => return respond(None, out_len),
    }
    respond(Some(writer.finish()), out_len)
}

/// Server-mode custom upstreams: `op u8 | fields`.
///
/// * `0` parse: `opt raw` -> records.
/// * `1` encode: records -> `json`.
/// * `2` validate: `name | protocol | address | port` -> kind (`6` is ok).
/// * `3` normalize address: `protocol | address` -> address.
/// * `4` server host port: `address | port` -> `host:port`.
///
/// # Safety
/// Same contract as [`diting_dns_config_core_tunnel`].
#[no_mangle]
pub unsafe extern "C" fn diting_dns_config_core_upstreams(
    input: *const u8,
    len: usize,
    out_len: *mut usize,
) -> *mut u8 {
    let mut reader = reader_at(input, len);
    let Some(op) = reader.u8() else {
        return respond(None, out_len);
    };
    let mut writer = Writer::new();
    header(&mut writer);
    match op {
        OP_PARSE_UPSTREAMS => {
            let Some(raw) = reader.opt_string() else {
                return respond(None, out_len);
            };
            write_upstreams(
                &mut writer,
                &upstreams::parse_custom_upstreams(raw.as_deref()),
            );
        }
        OP_ENCODE_UPSTREAMS => {
            let Some(records) = input::read_upstreams(&mut reader) else {
                return respond(None, out_len);
            };
            writer.string(&upstreams::encode_custom_upstreams(&records));
        }
        OP_VALIDATE_UPSTREAM => {
            let Some(name) = reader.string() else {
                return respond(None, out_len);
            };
            let Some(protocol) = read_protocol(&mut reader) else {
                return respond(None, out_len);
            };
            let Some(address) = reader.string() else {
                return respond(None, out_len);
            };
            let Some(port) = reader.i32() else {
                return respond(None, out_len);
            };
            writer.u8(match upstreams::validate(&name, protocol, &address, port) {
                Ok(()) => upstreams::UPSTREAM_OK,
                Err(kind) => kind as u8,
            });
        }
        OP_NORMALIZE_ADDRESS => {
            let Some(protocol) = read_protocol(&mut reader) else {
                return respond(None, out_len);
            };
            let Some(address) = reader.string() else {
                return respond(None, out_len);
            };
            writer.string(&upstreams::normalize_address(protocol, &address));
        }
        OP_SERVER_HOST_PORT => {
            let (Some(address), Some(port)) = (reader.string(), reader.i32()) else {
                return respond(None, out_len);
            };
            writer.string(&protocol::server_host_port(&address, port));
        }
        _ => return respond(None, out_len),
    }
    respond(Some(writer.finish()), out_len)
}

#[cfg(test)]
mod tests;
