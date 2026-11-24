use crate::paths;

use super::super::dnsstate::command_exists;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FirewallGen {
    Fw4,
    Fw3,
    UciOnly,
    None,
}

impl FirewallGen {
    pub fn as_str(self) -> &'static str {
        match self {
            FirewallGen::Fw4 => "uci-fw4",
            FirewallGen::Fw3 => "uci-fw3",
            FirewallGen::UciOnly => "uci",
            FirewallGen::None => "none",
        }
    }
}

pub fn is_openwrt() -> bool {
    paths::is_openwrt()
}

pub fn distro_description() -> String {
    paths::openwrt_distro_name().unwrap_or_else(|| "OpenWrt".to_string())
}

pub fn detect_firewall_gen() -> FirewallGen {
    let has_uci = command_exists("uci") || command_exists("/sbin/uci");
    if command_exists("fw4") || command_exists("/sbin/fw4") {
        FirewallGen::Fw4
    } else if command_exists("fw3") || command_exists("/sbin/fw3") {
        FirewallGen::Fw3
    } else if has_uci {
        FirewallGen::UciOnly
    } else {
        FirewallGen::None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn firewall_gen_labels_are_stable() {
        assert_eq!(FirewallGen::Fw4.as_str(), "uci-fw4");
        assert_eq!(FirewallGen::Fw3.as_str(), "uci-fw3");
        assert_eq!(FirewallGen::UciOnly.as_str(), "uci");
        assert_eq!(FirewallGen::None.as_str(), "none");
    }
}
