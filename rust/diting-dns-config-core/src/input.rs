//! Payload decoders for the two documents and for the record lists.
//!
//! Every field is positional; a short payload returns `None`, which the entry point reports as a
//! rejected call (a null pointer) rather than a half-read config.

use crate::bootstrap::BootstrapRow;
use crate::document::{BootstrapEntry, CacheInput, DynamicInput, ServerSettings, TunnelSettings};
use crate::protocol::{self, Protocol};
use crate::providers::Provider;
use crate::upstreams::ServerUpstream;
use crate::wire::Reader;

fn read_protocol(reader: &mut Reader<'_>) -> Option<Protocol> {
    let storage = reader.string()?;
    Some(protocol::from_storage(&storage).unwrap_or(Protocol::Plain))
}

pub fn read_providers(reader: &mut Reader<'_>) -> Option<Vec<Provider>> {
    let count = reader.u32()?;
    let mut providers = Vec::with_capacity(count.min(512) as usize);
    for _ in 0..count {
        let id = reader.string()?;
        let name = reader.string()?;
        let protocol = read_protocol(reader)?;
        let url = reader.string()?;
        let host = reader.string()?;
        let port = reader.i32()?;
        providers.push(Provider {
            id,
            name,
            protocol,
            url,
            host,
            port,
        });
    }
    Some(providers)
}

pub fn read_bootstrap(reader: &mut Reader<'_>) -> Option<Vec<BootstrapEntry>> {
    let count = reader.u32()?;
    let mut entries = Vec::with_capacity(count.min(256) as usize);
    for _ in 0..count {
        let id = reader.string()?;
        let name = reader.string()?;
        let ip = reader.string()?;
        entries.push(BootstrapEntry { id, name, ip });
    }
    Some(entries)
}

pub fn read_upstreams(reader: &mut Reader<'_>) -> Option<Vec<ServerUpstream>> {
    let count = reader.u32()?;
    let mut upstreams = Vec::with_capacity(count.min(512) as usize);
    for _ in 0..count {
        let id = reader.string()?;
        let name = reader.string()?;
        let protocol = read_protocol(reader)?;
        let address = reader.string()?;
        let port = reader.i32()?;
        upstreams.push(ServerUpstream {
            id,
            name,
            protocol,
            address,
            port,
        });
    }
    Some(upstreams)
}

pub fn read_bootstrap_rows(reader: &mut Reader<'_>) -> Option<Vec<BootstrapRow>> {
    let count = reader.u32()?;
    let mut rows = Vec::with_capacity(count.min(256) as usize);
    for _ in 0..count {
        let id = reader.string()?;
        let name = reader.string()?;
        let ip = reader.string()?;
        let enabled = reader.bool()?;
        rows.push(BootstrapRow {
            id,
            name,
            ip,
            enabled,
        });
    }
    Some(rows)
}

pub fn tunnel_settings(reader: &mut Reader<'_>) -> Option<TunnelSettings> {
    let flags = reader.u8()?;
    let mode_raw = reader.string()?;
    let selected_provider_id = reader.string()?;
    let smart_prediction_provider_ids = reader.strings()?;
    let parallel_race_provider_ids = reader.strings()?;
    let primary_backup_provider_ids = reader.strings()?;
    let user_providers_json = reader.opt_string()?;
    let bootstrap_preset_ids = reader.strings()?;
    let bootstrap_custom_json = reader.opt_string()?;
    let block_response_mode = reader.string()?;
    let cache_mode = reader.string()?;
    let cache = CacheInput {
        enabled: flags & 0b10 != 0,
        mode: cache_mode,
        max_ttl_seconds: reader.i32()?,
        fixed_ttl_seconds: reader.i32()?,
        min_ttl_enabled: flags & 0b100 != 0,
        min_ttl_seconds: reader.i32()?,
        stale_fallback_enabled: flags & 0b1000 != 0,
        stale_fallback_seconds: reader.i32()?,
    };
    let dynamic = DynamicInput {
        enabled: flags & 0b10000 != 0,
        request_threshold: reader.i32()?,
        window_seconds: reader.i32()?,
        nxdomain_seconds: reader.i32()?,
    };
    Some(TunnelSettings {
        mode_raw,
        selected_provider_id,
        smart_prediction_provider_ids,
        parallel_race_provider_ids,
        primary_backup_provider_ids,
        user_providers_json,
        bootstrap_enabled: flags & 0b1 != 0,
        bootstrap_preset_ids,
        bootstrap_custom_json,
        block_response_mode,
        cache,
        dynamic,
    })
}

pub fn server_settings(reader: &mut Reader<'_>) -> Option<ServerSettings> {
    let flags = reader.u8()?;
    let resolution_mode_raw = reader.string()?;
    let selected_upstream_id = reader.string()?;
    let smart_prediction_provider_ids = reader.strings()?;
    let parallel_race_provider_ids = reader.strings()?;
    let primary_backup_provider_ids = reader.strings()?;
    let port = reader.i32()?;
    let cache_preset_raw = reader.string()?;
    let block_response_mode = reader.string()?;
    let dynamic = DynamicInput {
        enabled: flags & 0b100 != 0,
        request_threshold: reader.i32()?,
        window_seconds: reader.i32()?,
        nxdomain_seconds: reader.i32()?,
    };
    let custom_upstreams_json = reader.opt_string()?;
    Some(ServerSettings {
        resolution_mode_raw,
        selected_upstream_id,
        smart_prediction_provider_ids,
        parallel_race_provider_ids,
        primary_backup_provider_ids,
        port,
        ad_block_enabled: flags & 0b1 != 0,
        cache_preset_raw,
        cache_enabled: flags & 0b10 != 0,
        block_response_mode,
        dynamic,
        custom_upstreams_json,
    })
}

#[cfg(test)]
mod tests;
