//! Adapter scanner backed by the native `GetAdaptersAddresses` enumeration.
//!
//! The executor parameter exists only to mirror the cross-platform constructor; Windows never
//! shells out for adapter scanning, and silently discarding an injected executor (as the Go
//! service's comment warns about) would be misleading, so it is retained but unused.

use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_api::platform_types::AdapterInfo;

use crate::error::PlatformResult;
use crate::exec::CommandExecutor;
use crate::netutil::has_valid_ipv4_gateway;
use crate::traits::AdapterScanner;

use super::adapter_native::scan_adapters_native;

pub struct WindowsAdapterScanner {
    _executor: Arc<dyn CommandExecutor>,
}

impl WindowsAdapterScanner {
    pub fn new(executor: Arc<dyn CommandExecutor>) -> Self {
        Self {
            _executor: executor,
        }
    }
}

#[async_trait]
impl AdapterScanner for WindowsAdapterScanner {
    async fn scan_all(&self) -> PlatformResult<Vec<AdapterInfo>> {
        scan_adapters_native()
    }

    /// Keeps the Go selection rule verbatim: physical, `Up`, and holding a routable IPv4
    /// gateway. No fallback adapter is invented; an empty result means takeover must not run.
    async fn active_physical_adapters(&self) -> PlatformResult<Vec<AdapterInfo>> {
        let all = self.scan_all().await?;
        Ok(all
            .into_iter()
            .filter(|adapter| {
                adapter.is_physical
                    && adapter.status.eq_ignore_ascii_case("Up")
                    && has_valid_ipv4_gateway(&adapter.gateway)
            })
            .collect())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selection_predicate_honours_gateway_and_status() {
        let physical_up = AdapterInfo {
            is_physical: true,
            status: "up".into(),
            gateway: "192.168.1.1".into(),
            ..AdapterInfo::default()
        };
        let virtual_adapter = AdapterInfo {
            is_physical: false,
            status: "Up".into(),
            gateway: "192.168.1.1".into(),
            ..AdapterInfo::default()
        };
        let no_gateway = AdapterInfo {
            is_physical: true,
            status: "Up".into(),
            gateway: "0.0.0.0".into(),
            ..AdapterInfo::default()
        };
        let predicate = |adapter: &AdapterInfo| {
            adapter.is_physical
                && adapter.status.eq_ignore_ascii_case("Up")
                && has_valid_ipv4_gateway(&adapter.gateway)
        };
        assert!(predicate(&physical_up));
        assert!(!predicate(&virtual_adapter));
        assert!(!predicate(&no_gateway));
    }
}
