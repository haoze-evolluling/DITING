#![allow(unused_imports)]

pub use diting_agent_core;
pub use diting_app_update_core;
pub use diting_backup_core;
pub use diting_captive_core;
pub use diting_cleanup_core;
pub use diting_dns_config_core;
pub use diting_event_core;
pub use diting_hit_core;
pub use diting_ip_quality_core;
pub use diting_leak_core;
pub use diting_log_core;
pub use diting_log_query_core;
pub use diting_netprofile_core;
pub use diting_notification_core;
pub use diting_outbound_proxy_core;
pub use diting_probe_core;
pub use diting_recognition_core;
pub use diting_response_core;
pub use diting_rule_core;
pub use diting_rule_import_core;
pub use diting_rule_store_core;
pub use diting_rule_version_core;
pub use diting_schedule_core;
pub use diting_services_core;
pub use diting_subscription_core;
pub use diting_vpn_config_core;

pub const KERNELS_ABI_VERSION: u32 = 1;

#[no_mangle]
pub extern "C" fn diting_kernels_abi_version() -> u32 {
    KERNELS_ABI_VERSION
}
