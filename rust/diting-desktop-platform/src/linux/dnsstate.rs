//! Current per-interface DNS discovery plus `/etc/resolv.conf` parsing and atomic writes.
//!
//! Ported from `dnsstate.go`, `resolvconf.go` and the relevant `backend_resolved.go` helpers.
//! The parsers are pure and unit-tested; only the `read_*`/`scan_*` entry points touch the system.

use std::collections::HashMap;
use std::io;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use regex::Regex;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::paths;

use super::adapter::{iface_usable_for_resolv_conf, list_managed_interfaces};
use super::files;

pub(crate) const RESOLV_CONF_PATH: &str = "/etc/resolv.conf";
pub(crate) const RESOLVED_DROP_DIR: &str = "/etc/systemd/resolved.conf.d";
pub(crate) const RESOLVED_DROP_FILE: &str = "/etc/systemd/resolved.conf.d/diting.conf";
pub(crate) const RESOLV_CONF_ORIGINAL_PATH: &str = "/etc/resolv.conf.diting.orig";

/// Contents of the drop-in that disables the systemd-resolved stub listener.
pub(crate) const RESOLVED_DROP_IN_CONTENT: &str =
    "# 由谛听 (DITING) 写入：关闭 systemd-resolved 的本地 stub 监听器，
# 释放 127.0.0.53:53 与 127.0.0.54:53 供谛听 DNS 服务绑定。
# 卸载谛听服务后可安全删除本文件并执行 systemctl restart systemd-resolved。
[Resolve]
DNSStubListener=no
";

fn link_line_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"^Link\s+\d+\s+\(([^)]+)\)\s*:?\s*(.*)$").expect("link line pattern compiles")
    })
}

/// True when `name` is a file in `PATH` (or an explicit path).
pub(crate) fn command_exists(name: &str) -> bool {
    if name.contains('/') {
        return std::fs::metadata(name)
            .map(|metadata| !metadata.is_dir())
            .unwrap_or(false);
    }
    let Some(path) = std::env::var_os("PATH") else {
        return false;
    };
    for directory in std::env::split_paths(&path) {
        if directory.as_os_str().is_empty() {
            continue;
        }
        if std::fs::metadata(directory.join(name))
            .map(|metadata| !metadata.is_dir())
            .unwrap_or(false)
        {
            return true;
        }
    }
    false
}

/// Probes the active DNS backend in the same order as Go: resolved → NetworkManager → file.
pub(crate) async fn scan_configured_dns_servers(
    executor: &dyn CommandExecutor,
) -> HashMap<String, Vec<String>> {
    if command_exists("resolvectl") {
        let servers = servers_from_resolvectl(executor).await;
        if !servers.is_empty() {
            return servers;
        }
    }
    if command_exists("nmcli") {
        let servers = servers_from_nmcli(executor).await;
        if !servers.is_empty() {
            return servers;
        }
    }
    servers_from_resolv_conf()
}

async fn servers_from_resolvectl(executor: &dyn CommandExecutor) -> HashMap<String, Vec<String>> {
    match executor.run("resolvectl", &["dns"]).await {
        Ok(output) if output.success => parse_resolvectl_dns(&output.text()),
        _ => HashMap::new(),
    }
}

/// Parses `resolvectl dns` link lines into interface → servers.
pub(crate) fn parse_resolvectl_dns(output: &str) -> HashMap<String, Vec<String>> {
    let mut result = HashMap::new();
    for line in output.lines() {
        let Some(captures) = link_line_regex().captures(line.trim()) else {
            continue;
        };
        let Some(iface) = captures.get(1) else {
            continue;
        };
        let iface = iface.as_str().trim();
        let servers: Vec<String> = captures
            .get(2)
            .map(|value| {
                value
                    .as_str()
                    .split_whitespace()
                    .map(str::to_string)
                    .collect()
            })
            .unwrap_or_default();
        if !iface.is_empty() && !servers.is_empty() {
            result.insert(iface.to_string(), servers);
        }
    }
    result
}

async fn servers_from_nmcli(executor: &dyn CommandExecutor) -> HashMap<String, Vec<String>> {
    match executor
        .run(
            "nmcli",
            &[
                "-t",
                "-f",
                "DEVICE,IP4.DNS,IP6.DNS",
                "con",
                "show",
                "--active",
            ],
        )
        .await
    {
        Ok(output) if output.success => parse_nmcli_dns(&output.text()),
        _ => HashMap::new(),
    }
}

/// Parses `nmcli -t` connection rows into device → servers.
pub(crate) fn parse_nmcli_dns(output: &str) -> HashMap<String, Vec<String>> {
    let mut result = HashMap::new();
    for line in output.lines() {
        let fields: Vec<&str> = line.split(':').collect();
        if fields.len() < 3 {
            continue;
        }
        let iface = fields[0].trim();
        if iface.is_empty() || iface == "lo" {
            continue;
        }
        let mut servers = Vec::new();
        for field in &fields[1..] {
            servers.extend(field.split_whitespace().map(str::to_string));
        }
        if !servers.is_empty() {
            result.insert(iface.to_string(), servers);
        }
    }
    result
}

/// Attributes `/etc/resolv.conf` servers to every usable interface.
fn servers_from_resolv_conf() -> HashMap<String, Vec<String>> {
    let servers = current_system_servers();
    if servers.is_empty() {
        return HashMap::new();
    }
    let interfaces = match list_managed_interfaces() {
        Ok(interfaces) => interfaces,
        Err(_) => return HashMap::new(),
    };
    let mut result = HashMap::new();
    for interface in interfaces {
        if !iface_usable_for_resolv_conf(&interface) {
            continue;
        }
        result.insert(interface.name, servers.clone());
    }
    result
}

/// Parses the `nameserver` directives of a resolv.conf body.
pub(crate) fn parse_resolv_conf(content: &str) -> Vec<String> {
    let mut servers = Vec::new();
    for line in content.lines() {
        let line = line.trim();
        if line.is_empty() || line.starts_with('#') || line.starts_with(';') {
            continue;
        }
        let fields: Vec<&str> = line.split_whitespace().collect();
        if fields.len() >= 2 && fields[0] == "nameserver" {
            servers.push(fields[1].to_string());
        }
    }
    servers
}

/// Renders a minimal resolv.conf pointing at `servers`.
pub(crate) fn render_resolv_conf(servers: &[String]) -> String {
    let mut content = String::from("# Generated by DITING. Do not edit manually.\n");
    for server in servers {
        content.push_str("nameserver ");
        content.push_str(server);
        content.push('\n');
    }
    content.push_str("options timeout:2 attempts:2\n");
    content
}

/// Reads the current `/etc/resolv.conf`.
pub(crate) fn read_resolv_conf() -> io::Result<String> {
    std::fs::read_to_string(RESOLV_CONF_PATH)
}

/// Returns `(is_symlink, resolved_target)` for `/etc/resolv.conf`.
pub(crate) fn resolv_conf_is_symlink() -> (bool, String) {
    match std::fs::symlink_metadata(RESOLV_CONF_PATH) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            let target = std::fs::canonicalize(RESOLV_CONF_PATH)
                .map(|path| path.to_string_lossy().into_owned())
                .unwrap_or_default();
            (true, target)
        }
        _ => (false, String::new()),
    }
}

/// Writes `/etc/resolv.conf` atomically, unlinking a symlink first so the write cannot tunnel
/// into a system-managed file.
pub(crate) fn write_resolv_conf_atomically(content: &str) -> PlatformResult<()> {
    let (is_link, target) = resolv_conf_is_symlink();
    if is_link {
        if !target.is_empty() {
            let _ = write_backup(&target, "resolv.conf");
        }
        files::remove_path(Path::new(RESOLV_CONF_PATH)).map_err(|error| {
            PlatformError::message(format!("解除 resolv.conf 符号链接失败: {error}"))
        })?;
    }

    let temporary = format!("{RESOLV_CONF_PATH}.diting.tmp");
    files::write_file_mode(Path::new(&temporary), content.as_bytes(), 0o644)
        .map_err(|error| PlatformError::message(format!("写入临时 resolv.conf 失败: {error}")))?;
    if let Err(error) = std::fs::rename(&temporary, RESOLV_CONF_PATH) {
        let _ = files::remove_path(Path::new(&temporary));
        return Err(PlatformError::message(format!(
            "替换 resolv.conf 失败: {error}"
        )));
    }
    Ok(())
}

/// Runtime backup path under `<data>/backups`.
pub(crate) fn backup_path_for(name: &str) -> PathBuf {
    paths::default_data_dir().join("backups").join(name)
}

/// Writes a backup into the data directory.
pub(crate) fn write_backup_content(name: &str, content: &str) -> io::Result<()> {
    let path = backup_path_for(name);
    files::write_file_mode(&path, content.as_bytes(), 0o600)
}

/// Reads a backup from the data directory.
pub(crate) fn read_backup_content(name: &str) -> io::Result<String> {
    let data = files::read_file_at(&backup_path_for(name))?;
    Ok(String::from_utf8_lossy(&data).into_owned())
}

/// Copies `source` into the data directory.
pub(crate) fn write_backup(source: &str, name: &str) -> io::Result<()> {
    let data = files::read_file_at(Path::new(source))?;
    let path = backup_path_for(name);
    files::write_file_mode(&path, &data, 0o600)
}

/// Writes the pre-takeover `/etc/resolv.conf` used by `restore-dns.sh`.
pub(crate) fn write_resolv_conf_original(content: &str) -> io::Result<()> {
    files::write_file_mode(
        Path::new(RESOLV_CONF_ORIGINAL_PATH),
        content.as_bytes(),
        0o600,
    )
}

/// Whether the resolved drop-in directory exists or can be created.
pub(crate) fn resolved_drop_in_supported() -> bool {
    if std::fs::metadata(RESOLVED_DROP_DIR).is_ok() {
        return true;
    }
    std::fs::create_dir_all(RESOLVED_DROP_DIR).is_ok()
}

/// Servers currently in `/etc/resolv.conf`, used for diagnostics.
pub(crate) fn current_system_servers() -> Vec<String> {
    let Ok(content) = read_resolv_conf() else {
        return Vec::new();
    };
    parse_resolv_conf(&content)
        .into_iter()
        .filter(|server| !server.trim().is_empty())
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolv_conf_parser_ignores_non_nameserver_lines() {
        let content = "# comment\n; another\nnameserver 192.168.1.1\n\
                       nameserver 2001:db8::1\nsearch example.com\noptions timeout:2\n";
        assert_eq!(
            parse_resolv_conf(content),
            vec!["192.168.1.1".to_string(), "2001:db8::1".to_string()]
        );
        assert!(parse_resolv_conf("").is_empty());
    }

    #[test]
    fn rendered_resolv_conf_round_trips() {
        let rendered = render_resolv_conf(&["127.0.0.1".to_string(), "::1".to_string()]);
        assert_eq!(
            parse_resolv_conf(&rendered),
            vec!["127.0.0.1".to_string(), "::1".to_string()]
        );
    }

    #[test]
    fn resolvectl_links_are_parsed() {
        let output = "Global:\nLink 2 (eth0): 192.168.1.1 2001:db8::1\n\
                      Link 3 (wlan0):\nLink 4 (docker0): 172.17.0.1\n";
        let parsed = parse_resolvectl_dns(output);
        assert_eq!(
            parsed.get("eth0"),
            Some(&vec!["192.168.1.1".to_string(), "2001:db8::1".to_string()])
        );
        assert!(!parsed.contains_key("wlan0"));
        assert_eq!(parsed.get("docker0"), Some(&vec!["172.17.0.1".to_string()]));
    }

    #[test]
    fn nmcli_rows_are_parsed() {
        let output = "eth0:1.1.1.1 8.8.8.8:2001:db8::1\nlo:127.0.0.1:\nbad-row\n";
        let parsed = parse_nmcli_dns(output);
        assert_eq!(
            parsed.get("eth0"),
            Some(&vec![
                "1.1.1.1".to_string(),
                "8.8.8.8".to_string(),
                "2001:db8::1".to_string()
            ])
        );
        assert!(!parsed.contains_key("lo"));
        assert!(!parsed.contains_key("bad-row"));
    }
}
