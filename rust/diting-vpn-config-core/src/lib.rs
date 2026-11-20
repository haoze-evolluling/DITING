mod jni_bridge;
mod route;
mod start;
pub mod watchdog;

pub use route::{
    ipv6_enabled, ipv6_probe_needed, route_plan, DNS_SERVER_V4, DNS_SERVER_V6,
    IPV4_BYPASS_LAN_ROUTES, IPV4_HIJACK_IPS, IPV6_HIJACK_IPS, VPN_ADDRESS_V4, VPN_ADDRESS_V6,
    VPN_MTU,
};
pub use start::{start_defaults, DEFAULT_OUTBOUND_PROXY};
