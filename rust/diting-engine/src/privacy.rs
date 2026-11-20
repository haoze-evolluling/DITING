use std::net::IpAddr;

pub fn is_private_or_loopback(text: &str) -> bool {
    match text.trim().parse::<IpAddr>() {
        Ok(IpAddr::V4(v4)) => {
            let octets = v4.octets();
            v4.is_private()
                || v4.is_loopback()
                || v4.is_link_local()
                || v4.is_unspecified()
                || v4.is_broadcast()
                || (octets[0] == 100 && (64..=127).contains(&octets[1]))
        }
        Ok(IpAddr::V6(v6)) => {
            if v6.is_loopback() || v6.is_unspecified() {
                return true;
            }
            let segments = v6.segments();
            let unique_local = (segments[0] & 0xfe00) == 0xfc00;
            let link_local = (segments[0] & 0xffc0) == 0xfe80;
            if unique_local || link_local {
                return true;
            }
            if let Some(v4) = v6.to_ipv4_mapped() {
                let octets = v4.octets();
                return v4.is_private()
                    || v4.is_loopback()
                    || v4.is_link_local()
                    || (octets[0] == 100 && (64..=127).contains(&octets[1]));
            }
            false
        }
        Err(_) => false,
    }
}

pub fn any_private<'a>(mut addresses: impl Iterator<Item = &'a str>) -> bool {
    addresses.any(is_private_or_loopback)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn private_and_loopback_ranges_are_rejected() {
        for ip in [
            "127.0.0.1",
            "10.1.2.3",
            "172.16.5.4",
            "192.168.1.1",
            "169.254.0.1",
            "100.64.0.1",
            "0.0.0.0",
            "::1",
            "fc00::1",
            "fe80::1",
            "::ffff:192.168.0.1",
        ] {
            assert!(is_private_or_loopback(ip), "{ip} should be private");
        }
    }

    #[test]
    fn public_addresses_pass() {
        for ip in ["1.1.1.1", "8.8.8.8", "2606:4700::1111", "100.63.0.1"] {
            assert!(!is_private_or_loopback(ip), "{ip} should be public");
        }
    }

    #[test]
    fn any_private_scans_the_answer() {
        assert!(any_private(["1.1.1.1", "10.0.0.1"].into_iter()));
        assert!(!any_private(["1.1.1.1", "8.8.8.8"].into_iter()));
    }
}
