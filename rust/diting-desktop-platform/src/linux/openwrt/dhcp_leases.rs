use std::collections::HashMap;
use std::net::IpAddr;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime};

const DEFAULT_LEASES_PATH: &str = "/tmp/dhcp.leases";
const DEFAULT_DHCP_UCI_PATH: &str = "/etc/config/dhcp";
const REFRESH_INTERVAL: Duration = Duration::from_secs(2);

struct CachedState {
    last_checked: Option<Instant>,
    leases_mtime: Option<SystemTime>,
    uci_mtime: Option<SystemTime>,
    entries: Arc<HashMap<IpAddr, String>>,
}

/// 零阻塞读取 OpenWrt DHCP 动态租约表与静态主机绑定：
/// 每 2 秒至多 stat 一次文件修改时间，未变化时直接命中内存快照。
pub struct DhcpLeaseTable {
    leases_path: PathBuf,
    uci_path: PathBuf,
    state: Mutex<CachedState>,
}

impl DhcpLeaseTable {
    pub fn new() -> Self {
        Self::with_paths(DEFAULT_LEASES_PATH, DEFAULT_DHCP_UCI_PATH)
    }

    pub fn with_paths(leases: impl Into<PathBuf>, uci: impl Into<PathBuf>) -> Self {
        Self {
            leases_path: leases.into(),
            uci_path: uci.into(),
            state: Mutex::new(CachedState {
                last_checked: None,
                leases_mtime: None,
                uci_mtime: None,
                entries: Arc::new(HashMap::new()),
            }),
        }
    }

    pub fn lookup(&self, ip: IpAddr) -> Option<String> {
        let snapshot = self.snapshot();
        snapshot.get(&normalize_ip(ip)).cloned()
    }

    pub fn snapshot(&self) -> Arc<HashMap<IpAddr, String>> {
        let now = Instant::now();
        {
            let guard = self
                .state
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            if let Some(last) = guard.last_checked {
                if now.duration_since(last) < REFRESH_INTERVAL {
                    return Arc::clone(&guard.entries);
                }
            }
        }

        let leases_mtime = file_mtime(&self.leases_path);
        let uci_mtime = file_mtime(&self.uci_path);
        {
            let mut guard = self
                .state
                .lock()
                .unwrap_or_else(|poisoned| poisoned.into_inner());
            guard.last_checked = Some(now);
            if guard.leases_mtime == leases_mtime && guard.uci_mtime == uci_mtime {
                return Arc::clone(&guard.entries);
            }
        }

        let mut map = HashMap::new();
        if let Ok(content) = std::fs::read_to_string(&self.leases_path) {
            for (ip, name) in parse_dhcp_leases(&content) {
                map.insert(ip, name);
            }
        }
        // UCI 静态绑定覆盖动态租约同名 IP，准确度更高。
        if let Ok(content) = std::fs::read_to_string(&self.uci_path) {
            for (ip, name) in parse_uci_static_hosts(&content) {
                map.insert(ip, name);
            }
        }
        let next = Arc::new(map);
        let mut guard = self
            .state
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner());
        guard.leases_mtime = leases_mtime;
        guard.uci_mtime = uci_mtime;
        guard.entries = Arc::clone(&next);
        next
    }
}

impl Default for DhcpLeaseTable {
    fn default() -> Self {
        Self::new()
    }
}

fn file_mtime(path: &Path) -> Option<SystemTime> {
    std::fs::metadata(path).ok()?.modified().ok()
}

fn normalize_ip(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(v6) => v6
            .to_ipv4_mapped()
            .map(IpAddr::V4)
            .unwrap_or(IpAddr::V6(v6)),
        other => other,
    }
}

/// 解析 `/tmp/dhcp.leases`：`<expiry> <mac> <ip> <hostname> [client_id]`
pub fn parse_dhcp_leases(content: &str) -> HashMap<IpAddr, String> {
    let mut map = HashMap::new();
    for line in content.lines() {
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() < 4 {
            continue;
        }
        let Ok(ip) = fields[2].parse::<IpAddr>() else {
            continue;
        };
        let hostname = fields[3].trim();
        if hostname.is_empty() || hostname == "*" {
            continue;
        }
        map.insert(normalize_ip(ip), hostname.to_string());
    }
    map
}

/// 解析 `/etc/config/dhcp` 中的 `config host` 静态租约块。
pub fn parse_uci_static_hosts(content: &str) -> HashMap<IpAddr, String> {
    let mut map = HashMap::new();
    let mut in_host = false;
    let mut current_name = String::new();
    let mut current_ips: Vec<IpAddr> = Vec::new();

    let flush = |map: &mut HashMap<IpAddr, String>, name: &mut String, ips: &mut Vec<IpAddr>| {
        if !name.is_empty() {
            for ip in ips.drain(..) {
                map.insert(normalize_ip(ip), name.clone());
            }
        } else {
            ips.clear();
        }
        name.clear();
    };

    for raw in content.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if let Some(rest) = line.strip_prefix("config ") {
            if in_host {
                flush(&mut map, &mut current_name, &mut current_ips);
            }
            let section_type = rest.split_whitespace().next().unwrap_or("");
            in_host = section_type == "host";
            continue;
        }
        if !in_host {
            continue;
        }
        if let Some(rest) = line
            .strip_prefix("option ")
            .or_else(|| line.strip_prefix("list "))
        {
            let mut parts = rest.splitn(2, char::is_whitespace);
            let key = parts.next().unwrap_or("").trim();
            let val = parts
                .next()
                .unwrap_or("")
                .trim()
                .trim_matches('\'')
                .trim_matches('"')
                .trim();
            match key {
                "name" if !val.is_empty() => current_name = val.to_string(),
                "ip" => {
                    for token in val.split_whitespace() {
                        if let Ok(ip) = token.parse::<IpAddr>() {
                            current_ips.push(ip);
                        }
                    }
                }
                _ => {}
            }
        }
    }
    if in_host {
        flush(&mut map, &mut current_name, &mut current_ips);
    }
    map
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_leases_and_skips_wildcards() {
        let sample = "\
1732450000 aa:bb:cc:dd:ee:01 192.168.1.101 MacBook-Pro 01:aa:bb:cc:dd:ee:01
1732450000 aa:bb:cc:dd:ee:02 192.168.1.102 * *
1732450000 aa:bb:cc:dd:ee:03 fd00::103 Home-NAS *
";
        let parsed = parse_dhcp_leases(sample);
        assert_eq!(
            parsed
                .get(&"192.168.1.101".parse().unwrap())
                .map(String::as_str),
            Some("MacBook-Pro")
        );
        assert!(!parsed.contains_key(&"192.168.1.102".parse().unwrap()));
        assert_eq!(
            parsed
                .get(&"fd00::103".parse().unwrap())
                .map(String::as_str),
            Some("Home-NAS")
        );
    }

    #[test]
    fn parses_uci_static_host_sections() {
        let uci = "\
config dnsmasq
\toption domain 'lan'

config host
\toption name 'LivingRoom-TV'
\toption mac '11:22:33:44:55:66'
\toption ip '192.168.1.50'

config domain
\toption name 'ignore-me'
\toption ip '192.168.1.99'
";
        let parsed = parse_uci_static_hosts(uci);
        assert_eq!(
            parsed
                .get(&"192.168.1.50".parse().unwrap())
                .map(String::as_str),
            Some("LivingRoom-TV")
        );
        assert!(!parsed.contains_key(&"192.168.1.99".parse().unwrap()));
    }
}
