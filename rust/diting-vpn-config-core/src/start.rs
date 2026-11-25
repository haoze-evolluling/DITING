use serde_json::{json, Value};

pub const DEFAULT_OUTBOUND_PROXY: &str = r#"{"enabled":false,"protocol":"SOCKS5","host":"127.0.0.1","port":7890,"username":"","password":""}"#;

pub fn start_defaults() -> Value {
    json!({
        "outboundProxy": DEFAULT_OUTBOUND_PROXY,
        "proxyAppPackage": "",
        "bypassLan": true,
        "ipv6Mode": "ipv4",
        "tunnelIpv6": false,
        "dnsAaaa": false,
        "routeAddress": [],
        "routeExcludeAddress": [],
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
        assert_eq!(defaults["ipv6Mode"], "ipv4");
        assert_eq!(defaults["tunnelIpv6"], false);
        assert_eq!(defaults["dnsAaaa"], false);
        assert_eq!(defaults["routeAddress"], json!([]));
        assert_eq!(defaults["routeExcludeAddress"], json!([]));
        assert_eq!(defaults["inspectionEnabled"], false);
        assert_eq!(defaults["excludedPackages"], json!([]));
        assert!(DEFAULT_OUTBOUND_PROXY.contains("\"protocol\":\"SOCKS5\""));
        assert!(DEFAULT_OUTBOUND_PROXY.contains("\"enabled\":false"));
    }
}
