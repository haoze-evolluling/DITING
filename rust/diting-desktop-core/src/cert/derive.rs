use std::collections::HashSet;
use std::net::IpAddr;

pub fn derive_cert_names(server_name: &str, listen_address: &str) -> (Vec<String>, Vec<String>) {
    let mut seen = HashSet::new();
    let mut dns_names = Vec::new();
    let mut ip_addresses = Vec::new();

    add_host(server_name, &mut seen, &mut dns_names, &mut ip_addresses);
    if let Some(host) = host_part(listen_address) {
        add_host(host, &mut seen, &mut dns_names, &mut ip_addresses);
    }

    dns_names.sort();
    (dns_names, ip_addresses)
}

pub fn host_part(listen_address: &str) -> Option<&str> {
    let address = listen_address.trim();
    if address.is_empty() {
        return None;
    }
    if let Some(rest) = address.strip_prefix('[') {
        let (host, _) = rest.split_once(']')?;
        return Some(host);
    }
    match address.rsplit_once(':') {
        Some((host, port)) if !host.contains(':') && !host.is_empty() && !port.is_empty() => {
            if port.chars().all(|character| character.is_ascii_digit()) {
                Some(host)
            } else {
                Some(address)
            }
        }
        _ => Some(address),
    }
}

fn add_host(
    raw: &str,
    seen: &mut HashSet<String>,
    dns_names: &mut Vec<String>,
    ip_addresses: &mut Vec<String>,
) {
    let host = raw.trim();
    if host.is_empty() {
        return;
    }
    match host.parse::<IpAddr>() {
        Ok(ip) => {
            if ip.is_unspecified() {
                return;
            }
            if seen.insert(format!("i:{ip}")) {
                ip_addresses.push(ip.to_string());
            }
        }
        Err(_) => {
            if seen.insert(format!("d:{host}")) {
                dns_names.push(host.to_string());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn derives_name_and_loopback_ip() {
        let (dns, ips) = derive_cert_names("dns.lan", "127.0.0.1");
        assert_eq!(dns, vec!["dns.lan"]);
        assert_eq!(ips, vec!["127.0.0.1"]);
    }

    #[test]
    fn strips_ports_and_brackets() {
        assert_eq!(host_part("[::1]:853"), Some("::1"));
        assert_eq!(host_part("127.0.0.1:53"), Some("127.0.0.1"));
        assert_eq!(host_part("::1"), Some("::1"));
        assert_eq!(host_part("dns.lan"), Some("dns.lan"));
    }

    #[test]
    fn wildcard_addresses_are_skipped() {
        let (dns, ips) = derive_cert_names("dns.lan", "0.0.0.0");
        assert_eq!(dns, vec!["dns.lan"]);
        assert!(ips.is_empty());
        let (_, ips) = derive_cert_names("", "[::]");
        assert!(ips.is_empty());
    }

    #[test]
    fn duplicates_are_dropped_and_names_sorted() {
        let (dns, ips) = derive_cert_names("dns.lan", "[::1]:853");
        assert_eq!(dns, vec!["dns.lan"]);
        assert_eq!(ips, vec!["::1"]);
        let (_, ips) = derive_cert_names("1.2.3.4", "1.2.3.4");
        assert_eq!(ips, vec!["1.2.3.4"]);
    }
}
