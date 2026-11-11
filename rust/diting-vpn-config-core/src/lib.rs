//! TUN route plans and start defaults for the Android VPN services.
//!
//! Kotlin keeps `VpnService.Builder`, the interface label, `ParcelFileDescriptor`, SharedPreferences
//! and the ConnectivityManager probe. Everything that decides what enters the tunnel - addresses,
//! DNS servers, the 50 bypass-LAN ranges, express mode's resolver routes, MTU, blocking, the IPv6
//! mode and the excluded-package union - lives in [`route`]. [`start`] holds the defaults the
//! quick-settings tile replays when it has never seen a start.
//!
//! The plan crosses JNI as JSON (`com.haoze.diting.vpn.VpnPlanNative`). A missing library throws
//! before `Builder.establish()`, so a build that forgot `python rust/build_android.py` cannot start
//! a tunnel with a different routing table. [`watchdog`] is the state machine Kotlin's
//! `VpnChannelWatchdog` drives with its Handler and ConnectivityManager callback.

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
