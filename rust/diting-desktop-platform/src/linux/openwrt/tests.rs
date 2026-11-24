use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use async_trait::async_trait;
use diting_desktop_api::config::{
    OpenWrtConfig, OPENWRT_MODE_DNSMASQ_UPSTREAM, OPENWRT_MODE_REPLACE_DNSMASQ,
};

use crate::error::PlatformResult;
use crate::exec::{CommandExecutor, CommandOutput};
use crate::state::FileStateStore;
use crate::traits::DnsManager;

use super::{OpenWrtDnsManager, OpenWrtFirewall};

#[derive(Default)]
struct MockUciSystem {
    kv: Mutex<HashMap<String, Vec<String>>>,
    calls: Mutex<Vec<String>>,
}

impl MockUciSystem {
    fn new() -> Self {
        let mut map = HashMap::new();
        map.insert("dhcp.@dnsmasq[0].domain".into(), vec!["lan".into()]);
        map.insert(
            "dhcp.@dnsmasq[0].server".into(),
            vec!["114.114.114.114".into()],
        );
        Self {
            kv: Mutex::new(map),
            calls: Mutex::new(Vec::new()),
        }
    }

    fn get_single(&self, key: &str) -> Option<String> {
        self.kv
            .lock()
            .unwrap()
            .get(key)
            .and_then(|v| v.first().cloned())
    }

    fn get_all(&self, key: &str) -> Vec<String> {
        self.kv
            .lock()
            .unwrap()
            .get(key)
            .cloned()
            .unwrap_or_default()
    }
}

#[async_trait]
impl CommandExecutor for MockUciSystem {
    async fn run(&self, program: &str, args: &[&str]) -> PlatformResult<CommandOutput> {
        self.calls
            .lock()
            .unwrap()
            .push(format!("{program} {}", args.join(" ")));

        if program == "uci" {
            let filtered: Vec<&str> = args.iter().copied().filter(|arg| *arg != "-q").collect();
            match filtered.as_slice() {
                ["get", key] | ["-d", "\n", "get", key] => {
                    let guard = self.kv.lock().unwrap();
                    if let Some(vals) = guard.get(*key) {
                        return Ok(CommandOutput {
                            stdout: vals.join("\n").into_bytes(),
                            status: Some(0),
                            success: true,
                        });
                    }
                    return Ok(CommandOutput {
                        stdout: Vec::new(),
                        status: Some(1),
                        success: false,
                    });
                }
                ["set", expr] => {
                    if let Some((k, v)) = expr.split_once('=') {
                        self.kv
                            .lock()
                            .unwrap()
                            .insert(k.to_string(), vec![v.to_string()]);
                    }
                }
                ["add_list", expr] => {
                    if let Some((k, v)) = expr.split_once('=') {
                        self.kv
                            .lock()
                            .unwrap()
                            .entry(k.to_string())
                            .or_default()
                            .push(v.to_string());
                    }
                }
                ["delete", key] => {
                    self.kv.lock().unwrap().remove(*key);
                }
                ["commit", _] => {}
                _ => {}
            }
        }
        Ok(CommandOutput {
            stdout: Vec::new(),
            status: Some(0),
            success: true,
        })
    }
}

fn temp_dir(tag: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!(
        "diting-openwrt-test-{tag}-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    let _ = std::fs::create_dir_all(&dir);
    dir
}

#[tokio::test]
async fn dual_mode_switch_preserves_original_backup_and_restores_cleanly() {
    let dir = temp_dir("dual-mode");
    let mock = Arc::new(MockUciSystem::new());
    let store = Arc::new(FileStateStore::new(dir.join("dns_state.json")));
    let firewall = Arc::new(OpenWrtFirewall::new(mock.clone()));
    let manager = OpenWrtDnsManager::new(
        mock.clone(),
        store,
        firewall,
        OpenWrtConfig::default(),
        "2.7.1",
    );

    // 1. 默认模式 A：接管 53 端口，dnsmasq 迁至 5353
    manager.takeover(&[]).await.unwrap();
    assert!(manager.is_takeover_active());
    assert_eq!(
        mock.get_single("dhcp.@dnsmasq[0].port").as_deref(),
        Some("5353")
    );
    assert_eq!(manager.detected_local_domain(), "lan");

    // 2. 在线切换为模式 B：作为 dnsmasq 上游（不应覆盖原始备份 114.114.114.114）
    manager.set_openwrt_config(OpenWrtConfig {
        mode: OPENWRT_MODE_DNSMASQ_UPSTREAM.to_string(),
        dnsmasq_port: 5353,
        upstream_port: 5354,
        forward_local_domain: true,
        force_redirect_53: false,
        desired_active: true,
    });
    manager.takeover(&[]).await.unwrap();
    assert_eq!(mock.get_single("dhcp.@dnsmasq[0].port"), None);
    assert_eq!(
        mock.get_single("dhcp.@dnsmasq[0].noresolv").as_deref(),
        Some("1")
    );
    assert_eq!(
        mock.get_all("dhcp.@dnsmasq[0].server"),
        vec!["127.0.0.1#5354".to_string()]
    );
    assert_eq!(
        manager.taken_over_adapters()[0].id,
        OPENWRT_MODE_DNSMASQ_UPSTREAM
    );

    // 3. 切回模式 A
    manager.set_openwrt_config(OpenWrtConfig {
        mode: OPENWRT_MODE_REPLACE_DNSMASQ.to_string(),
        ..manager.openwrt_config()
    });
    manager.takeover(&[]).await.unwrap();
    assert_eq!(
        mock.get_single("dhcp.@dnsmasq[0].port").as_deref(),
        Some("5353")
    );

    // 4. 还原：精确恢复接管前的端口（无显式 port=默认 53）与原始上游 114.114.114.114
    manager.restore().await.unwrap();
    assert!(!manager.is_takeover_active());
    assert_eq!(mock.get_single("dhcp.@dnsmasq[0].port"), None);
    assert_eq!(mock.get_single("dhcp.@dnsmasq[0].noresolv"), None);
    assert_eq!(
        mock.get_all("dhcp.@dnsmasq[0].server"),
        vec!["114.114.114.114".to_string()]
    );
    assert!(manager.read_backup().is_none());

    let _ = std::fs::remove_dir_all(&dir);
}
