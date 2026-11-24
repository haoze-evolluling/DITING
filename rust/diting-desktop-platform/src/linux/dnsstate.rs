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
pub(crate) const RESOLV_CONF_SYMLINK_RECORD: &str = "resolv.conf.symlink";

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

/// resolvectl 在 D-Bus 不可用时仍可能以 0 退出，只输出错误文本，
/// 因此检测后端不能只看退出码，必须排除这些错误输出。
pub(crate) fn resolvectl_status_usable(text: &str) -> bool {
    if text.is_empty() {
        return false;
    }
    let lower = text.to_ascii_lowercase();
    !lower.contains("failed to")
        && !lower.contains("sd_bus_open_system")
        && !lower.contains("could not")
        && !lower.contains("no such file")
}

/// `nmcli con show` 只接受 GENERAL/连接字段，`IP4.DNS` 不是合法字段。
/// 因此先取活动连接与设备映射，再逐个读取连接的 `ipv4.dns/ipv6.dns` 属性。
async fn servers_from_nmcli(executor: &dyn CommandExecutor) -> HashMap<String, Vec<String>> {
    let output = match executor
        .run(
            "nmcli",
            &["-t", "-f", "NAME,DEVICE,STATE", "con", "show", "--active"],
        )
        .await
    {
        Ok(output) if output.success => output,
        _ => return HashMap::new(),
    };

    let mut result = HashMap::new();
    for line in output.text().lines() {
        let fields = split_terse_fields(line);
        if fields.len() < 3 {
            continue;
        }
        let name = fields[0].trim();
        let device = fields[1].trim();
        if name.is_empty() || device.is_empty() || name == "lo" || device == "lo" {
            continue;
        }
        let properties = match executor
            .run(
                "nmcli",
                &["-t", "-f", "ipv4.dns,ipv6.dns", "con", "show", name],
            )
            .await
        {
            Ok(output) if output.success => output,
            _ => continue,
        };
        let servers = parse_nmcli_dns_properties(&properties.text());
        if !servers.is_empty() {
            result.insert(device.to_string(), servers);
        }
    }
    result
}

/// nmcli 的 terse 模式（`-t`）用 `:` 分隔字段，并把值中的 `:` 转义为 `\:`。
/// 直接 `split(':')` 会截断 IPv6 地址，因此必须按转义规则解析。
pub(crate) fn split_terse_fields(line: &str) -> Vec<String> {
    let mut fields = Vec::new();
    let mut current = String::new();
    let mut escaped = false;
    for character in line.chars() {
        if escaped {
            current.push(character);
            escaped = false;
            continue;
        }
        match character {
            '\\' => escaped = true,
            ':' => fields.push(std::mem::take(&mut current)),
            other => current.push(other),
        }
    }
    if escaped {
        current.push('\\');
    }
    fields.push(current);
    fields
}

/// 解析 `nmcli -t -f ipv4.dns,ipv6.dns con show <name>` 的输出。
/// 属性值可能包含 IPv6 地址和多值逗号列表，因此只在第一个 `:` 处切分。
pub(crate) fn parse_nmcli_dns_properties(output: &str) -> Vec<String> {
    let mut servers = Vec::new();
    for line in output.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let key = key.trim();
        if key != "ipv4.dns" && key != "ipv6.dns" {
            continue;
        }
        let value = value.replace("\\:", ":").replace("\\\\", "\\");
        for entry in value.split(',') {
            for server in entry.split_whitespace() {
                if !server.is_empty() {
                    servers.push(server.to_string());
                }
            }
        }
    }
    servers
}

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

pub(crate) fn read_resolv_conf() -> io::Result<String> {
    std::fs::read_to_string(RESOLV_CONF_PATH)
}

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

pub(crate) fn write_resolv_conf_atomically(content: &str) -> PlatformResult<()> {
    let (is_link, target) = resolv_conf_is_symlink();
    if is_link {
        if !target.is_empty() && !backup_exists("resolv.conf") {
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

pub(crate) fn backup_path_for(name: &str) -> PathBuf {
    paths::default_data_dir().join("backups").join(name)
}

pub(crate) fn backup_exists(name: &str) -> bool {
    files::file_exists(&backup_path_for(name))
}

pub(crate) fn clear_backup(name: &str) {
    let _ = files::remove_file_if_exists(&backup_path_for(name));
}

pub(crate) fn write_backup_content(name: &str, content: &str) -> io::Result<()> {
    let path = backup_path_for(name);
    files::write_file_mode(&path, content.as_bytes(), 0o600)
}

pub(crate) fn read_backup_content(name: &str) -> io::Result<String> {
    let data = files::read_file_at(&backup_path_for(name))?;
    Ok(String::from_utf8_lossy(&data).into_owned())
}

pub(crate) fn write_backup(source: &str, name: &str) -> io::Result<()> {
    let data = files::read_file_at(Path::new(source))?;
    let path = backup_path_for(name);
    files::write_file_mode(&path, &data, 0o600)
}

pub(crate) fn write_resolv_conf_original(content: &str) -> io::Result<()> {
    files::write_file_mode(
        Path::new(RESOLV_CONF_ORIGINAL_PATH),
        content.as_bytes(),
        0o600,
    )
}

/// 仅备份仍指向真实解析器的配置。若文件已被本服务接管（全是回环地址），
/// 再次接管时不能覆盖首次备份，否则还原后会指向一个已经停止的解析器。
pub(crate) fn should_preserve_resolv_conf(content: &str) -> bool {
    parse_resolv_conf(content)
        .iter()
        .any(|server| !crate::netutil::is_loopback_or_local_ip(server))
}

/// 记录 /etc/resolv.conf 原本是否为符号链接及其目标，供还原时恢复原形态。
/// 记录只写一次：后续接管时 resolv.conf 已被替换为普通文件。
pub(crate) fn record_resolv_conf_symlink() -> io::Result<()> {
    let record = backup_path_for(RESOLV_CONF_SYMLINK_RECORD);
    if files::file_exists(&record) {
        return Ok(());
    }
    let (is_link, target) = resolv_conf_is_symlink();
    if !is_link || target.is_empty() {
        return Ok(());
    }
    files::write_file_mode(&record, target.as_bytes(), 0o600)
}

pub(crate) fn recorded_resolv_conf_symlink() -> Option<String> {
    let target = read_backup_content(RESOLV_CONF_SYMLINK_RECORD).ok()?;
    let target = target.trim();
    (!target.is_empty()).then(|| target.to_string())
}

pub(crate) fn clear_resolv_conf_symlink_record() {
    let _ = files::remove_file_if_exists(&backup_path_for(RESOLV_CONF_SYMLINK_RECORD));
}

/// 还原 /etc/resolv.conf：优先恢复原来的符号链接形态，其次写入备份内容。
pub(crate) fn restore_resolv_conf(content: &str) -> PlatformResult<()> {
    if let Some(target) = recorded_resolv_conf_symlink() {
        if Path::new(&target).is_file() {
            files::remove_file_if_exists(Path::new(RESOLV_CONF_PATH)).map_err(|error| {
                PlatformError::message(format!("移除 resolv.conf 失败: {error}"))
            })?;
            #[cfg(unix)]
            std::os::unix::fs::symlink(&target, RESOLV_CONF_PATH).map_err(|error| {
                PlatformError::message(format!("恢复 resolv.conf 符号链接失败: {error}"))
            })?;
            clear_resolv_conf_symlink_record();
            return Ok(());
        }
    }
    let result = write_resolv_conf_atomically(content);
    if result.is_ok() {
        clear_resolv_conf_symlink_record();
    }
    result
}

pub(crate) fn resolved_drop_in_supported() -> bool {
    if std::fs::metadata(RESOLVED_DROP_DIR).is_ok() {
        return true;
    }
    std::fs::create_dir_all(RESOLVED_DROP_DIR).is_ok()
}

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
    fn loopback_only_resolv_conf_is_not_preserved_as_backup() {
        assert!(!should_preserve_resolv_conf(
            "nameserver 127.0.0.1\nnameserver ::1\noptions timeout:2\n"
        ));
        assert!(should_preserve_resolv_conf(
            "nameserver 192.168.1.1\nnameserver 127.0.0.1\n"
        ));
        assert!(!should_preserve_resolv_conf("# empty\n"));
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
    fn terse_fields_unescape_colons_and_backslashes() {
        assert_eq!(
            split_terse_fields("Wired connection 1:eth0:activated"),
            vec![
                "Wired connection 1".to_string(),
                "eth0".to_string(),
                "activated".to_string()
            ]
        );
        assert_eq!(
            split_terse_fields(r"Office\: floor 2:eth0:activated"),
            vec![
                "Office: floor 2".to_string(),
                "eth0".to_string(),
                "activated".to_string()
            ]
        );
        assert_eq!(
            split_terse_fields(r"a\\b:eth0:activated"),
            vec![
                "a\\b".to_string(),
                "eth0".to_string(),
                "activated".to_string()
            ]
        );
    }

    #[test]
    fn nmcli_dns_properties_keep_ipv6_and_multiple_servers() {
        let output = "ipv4.dns:1.1.1.1,8.8.8.8\nipv6.dns:2001:db8::1\n";
        assert_eq!(
            parse_nmcli_dns_properties(output),
            vec![
                "1.1.1.1".to_string(),
                "8.8.8.8".to_string(),
                "2001:db8::1".to_string()
            ]
        );
        assert!(parse_nmcli_dns_properties("ipv4.dns:\nipv6.dns:\n").is_empty());
    }

    #[test]
    fn resolvectl_error_output_is_not_treated_as_active() {
        assert!(resolvectl_status_usable(
            "Global\n  DNS Servers: 10.0.0.1\nLink 2 (eth0): 10.0.0.1\n"
        ));
        assert!(!resolvectl_status_usable(
            "Failed to get global data: Unit dbus-org.freedesktop.resolve1.service failed to load properly"
        ));
        assert!(!resolvectl_status_usable(
            "sd_bus_open_system: No such file or directory"
        ));
        assert!(!resolvectl_status_usable(""));
    }
}
