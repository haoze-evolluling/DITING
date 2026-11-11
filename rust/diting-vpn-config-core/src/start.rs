//! Defaults the quick-settings tile replays when it has never seen a start.
//!
//! The outbound-proxy document is deliberately the disabled legacy form: it stops the engine from
//! logging a parse failure while the user has never configured a proxy.

use serde_json::{json, Value};

/// Kept byte-for-byte identical to the legacy Kotlin constant.
pub const DEFAULT_OUTBOUND_PROXY: &str = r#"{"enabled":false,"protocol":"SOCKS5","host":"127.0.0.1","port":7890,"username":"","password":""}"#;

pub fn start_defaults() -> Value {
    json!({
        "outboundProxy": DEFAULT_OUTBOUND_PROXY,
        "proxyAppPackage": "",
        "bypassLan": true,
        "ipv6Mode": "auto",
        "excludedPackages": [],
        "blockedPackages": [],
        "inspectionPackages": [],
        "inspectionEnabled": false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_match_the_legacy_restore_chain() {
        let defaults = start_defaults();
        assert_eq!(defaults["outboundProxy"], DEFAULT_OUTBOUND_PROXY);
        assert_eq!(defaults["bypassLan"], true);
        assert_eq!(defaults["ipv6Mode"], "auto");
        assert_eq!(defaults["inspectionEnabled"], false);
        assert_eq!(defaults["excludedPackages"], json!([]));
        assert!(DEFAULT_OUTBOUND_PROXY.contains("\"protocol\":\"SOCKS5\""));
        assert!(DEFAULT_OUTBOUND_PROXY.contains("\"enabled\":false"));
    }
}
