//! Generates the offline `restore-dns.sh` script next to the state file.

use std::path::Path;

use chrono::Local;
use diting_desktop_api::platform_types::AdapterState;

use crate::error::{PlatformError, PlatformResult};
use crate::netutil::clean_adapter_state;

use super::backend::{interface_name_from_state, merge_dual_stack_servers, DnsBackend};
use super::files;

/// Writes the emergency restore script for the active backend.
pub fn generate_restore_script(
    backend: DnsBackend,
    adapters: &[AdapterState],
    output_path: &Path,
) -> PlatformResult<()> {
    let timestamp = Local::now().format("%Y-%m-%d %H:%M:%S");
    let mut script = String::new();
    script.push_str("#!/bin/sh\n");
    script.push_str("# ================================================================\n");
    script.push_str("#   谛听 (DITING) 紧急离线 DNS 还原脚本\n");
    script.push_str(&format!("#   生成时间: {timestamp}\n"));
    script.push_str(&format!("#   接管后端: {}\n", backend.as_str()));
    script.push_str("# ================================================================\n\n");
    script.push_str("set -u\n\n");
    script.push_str("if [ \"$(id -u)\" != \"0\" ]; then\n");
    script.push_str("    echo \"[错误] 请以 root 身份运行：sudo sh $0\" >&2\n");
    script.push_str("    exit 1\n");
    script.push_str("fi\n\n");
    script.push_str("echo \"[1/3] 备份当前 /etc/resolv.conf ...\"\n");
    script.push_str("cp -a /etc/resolv.conf /etc/resolv.conf.diting.bak 2>/dev/null || true\n\n");
    script.push_str("echo \"[2/3] 还原网卡 DNS 配置 ...\"\n");

    match backend {
        DnsBackend::SystemdResolved => write_resolved_restore(&mut script, adapters),
        DnsBackend::NetworkManager => write_network_manager_restore(&mut script, adapters),
        DnsBackend::ResolvConf | DnsBackend::None => {
            write_resolv_conf_restore(&mut script, adapters)
        }
    }

    script.push_str("\necho \"[3/3] 刷新系统 DNS 解析缓存 ...\"\n");
    script.push_str("command -v resolvectl >/dev/null 2>&1 && resolvectl flush-caches || true\n");
    script.push_str(
        "command -v systemd-resolve >/dev/null 2>&1 && systemd-resolve --flush-caches || true\n\n",
    );
    script.push_str("echo \"============================================================\"\n");
    script.push_str("echo \"系统 DNS 设置已还原。若解析仍异常，可手动编辑 /etc/resolv.conf\"\n");
    script.push_str("echo \"或执行 'wsl --shutdown'（WSL 环境）后重新进入以重置网络。\"\n");
    script.push_str("echo \"============================================================\"\n");

    if let Some(directory) = output_path.parent() {
        std::fs::create_dir_all(directory)
            .map_err(|error| PlatformError::message(format!("创建恢复脚本目录失败: {error}")))?;
    }
    files::write_file_mode(output_path, script.as_bytes(), 0o755)
        .map_err(|error| PlatformError::message(format!("写入恢复脚本失败: {error}")))
}

fn write_resolved_restore(script: &mut String, adapters: &[AdapterState]) {
    for raw in adapters {
        let adapter = clean_adapter_state(raw);
        let iface = interface_name_from_state(&adapter);
        if iface.is_empty() {
            continue;
        }

        let servers = merge_dual_stack_servers(&adapter);
        script.push_str(&format!("echo \"  还原网卡 [{iface}] ...\"\n"));
        if servers.is_empty() {
            script.push_str(&format!("resolvectl revert {iface} 2>/dev/null || true\n"));
            continue;
        }
        script.push_str(&format!(
            "resolvectl dns {iface} {} 2>/dev/null || true\n",
            servers.join(" ")
        ));
        script.push_str(&format!(
            "resolvectl domain {iface} '~.' 2>/dev/null || true\n"
        ));
    }
}

fn write_network_manager_restore(script: &mut String, adapters: &[AdapterState]) {
    for raw in adapters {
        let adapter = clean_adapter_state(raw);
        let name = interface_name_from_state(&adapter);
        if name.is_empty() {
            continue;
        }

        let ipv4 = adapter.ipv4_dns.join(",");
        let ipv6 = adapter.ipv6_dns.join(",");
        script.push_str(&format!("echo \"  还原连接 [{name}] ...\"\n"));
        script.push_str(&format!(
            "nmcli con mod {} ipv4.dns {} ipv6.dns {} \\\n",
            quote(name),
            quote(&ipv4),
            quote(&ipv6)
        ));
        script
            .push_str("    ipv4.ignore-auto-dns no ipv6.ignore-auto-dns no 2>/dev/null || true\n");
        script.push_str(&format!(
            "nmcli con up {} 2>/dev/null || true\n",
            quote(name)
        ));
    }
}

fn write_resolv_conf_restore(script: &mut String, adapters: &[AdapterState]) {
    let servers = collect_snapshot_servers(adapters);
    script.push_str("if [ -f /etc/resolv.conf.diting.orig ]; then\n");
    script.push_str("    echo \"  从接管前备份还原 /etc/resolv.conf ...\"\n");
    script.push_str("    cat /etc/resolv.conf.diting.orig > /etc/resolv.conf\n");
    script.push_str("else\n");
    script.push_str("    echo \"  写入接管前记录的解析服务器 ...\"\n");
    script.push_str("    {\n");
    script.push_str("        echo '# Restored by DITING.'\n");
    if servers.is_empty() {
        script.push_str("        echo 'nameserver 223.5.5.5'\n");
        script.push_str("        echo 'nameserver 119.29.29.29'\n");
    }
    for server in &servers {
        script.push_str(&format!("        echo 'nameserver {server}'\n"));
    }
    script.push_str("    } > /etc/resolv.conf\n");
    script.push_str("fi\n");
}

fn collect_snapshot_servers(adapters: &[AdapterState]) -> Vec<String> {
    let mut seen = std::collections::HashSet::new();
    let mut servers = Vec::new();
    for raw in adapters {
        for server in merge_dual_stack_servers(&clean_adapter_state(raw)) {
            if seen.insert(server.clone()) {
                servers.push(server);
            }
        }
    }
    servers
}

/// Minimal Go-style `%q` quoting for the shell-visible connection name and DNS lists.
fn quote(value: &str) -> String {
    let mut quoted = String::from("\"");
    for character in value.chars() {
        match character {
            '"' => quoted.push_str("\\\""),
            '\\' => quoted.push_str("\\\\"),
            '\n' => quoted.push_str("\\n"),
            '\r' => quoted.push_str("\\r"),
            '\t' => quoted.push_str("\\t"),
            other => quoted.push(other),
        }
    }
    quoted.push('"');
    quoted
}

#[cfg(test)]
mod tests {
    use super::quote;

    #[test]
    fn quoting_escapes_shell_significant_characters() {
        assert_eq!(quote("eth0"), "\"eth0\"");
        assert_eq!(quote("a\"b"), "\"a\\\"b\"");
        assert_eq!(quote(""), "\"\"");
    }
}
