use std::path::Path;

use diting_desktop_api::platform_types::AdapterState;

use crate::error::{PlatformError, PlatformResult};

use super::adapter_native::clean_state_for_windows;

fn batch_echo_text(text: &str) -> String {
    let mut escaped = String::with_capacity(text.len());
    for character in text.chars() {
        match character {
            '^' => escaped.push_str("^^"),
            '%' => escaped.push_str("%%"),
            '&' => escaped.push_str("^&"),
            '|' => escaped.push_str("^|"),
            '<' => escaped.push_str("^<"),
            '>' => escaped.push_str("^>"),
            '(' => escaped.push_str("^("),
            ')' => escaped.push_str("^)"),
            _ => escaped.push(character),
        }
    }
    escaped
}

fn batch_quoted_arg(text: &str) -> PlatformResult<String> {
    if text.contains(['"', '\r', '\n']) {
        return Err(PlatformError::message(format!(
            "网卡名称含无法安全写入批处理的字符: {text:?}"
        )));
    }
    Ok(text.replace('%', "%%"))
}

pub(crate) fn generate_restore_script(
    adapters: &[AdapterState],
    output_path: &Path,
) -> PlatformResult<()> {
    let timestamp = chrono::Local::now().format("%Y-%m-%d %H:%M:%S");
    let mut script = String::new();

    script.push_str("@echo off\r\n");
    script.push_str("chcp 65001 >nul\r\n");
    script.push_str("echo ================================================================\r\n");
    script.push_str("echo   谛听 (DITING) 紧急离线 DNS 还原脚本\r\n");
    script.push_str(&format!("echo   生成时间: {timestamp}\r\n"));
    script
        .push_str("echo ================================================================\r\n\r\n");
    script.push_str("net session >nul 2>&1\r\n");
    script.push_str("if %errorlevel% neq 0 (\r\n");
    script.push_str("    echo [错误] 请右键点击此批处理脚本，选择【以管理员身份运行】！\r\n");
    script.push_str("    pause\r\n");
    script.push_str("    exit /b 1\r\n");
    script.push_str(")\r\n\r\n");
    script.push_str("echo [1/2] 正在还原网卡 DNS 配置...\r\n");

    for raw in adapters {
        let adapter = clean_state_for_windows(raw);
        let name = batch_quoted_arg(&adapter.name)?;
        script.push_str(&format!(
            "echo 正在恢复适配器 [{}] ...\r\n",
            batch_echo_text(&adapter.name)
        ));

        if adapter.ipv4_dhcp || adapter.ipv4_dns.is_empty() {
            script.push_str(&format!(
                "netsh interface ipv4 set dnsservers name=\"{name}\" source=dhcp\r\n"
            ));
        } else {
            for (index, dns) in adapter.ipv4_dns.iter().enumerate() {
                if index == 0 {
                    script.push_str(&format!(
                        "netsh interface ipv4 set dnsservers name=\"{name}\" static {dns} primary validate=no\r\n"
                    ));
                } else {
                    script.push_str(&format!(
                        "netsh interface ipv4 add dnsservers name=\"{name}\" {dns} index={} validate=no\r\n",
                        index + 1
                    ));
                }
            }
        }

        if adapter.ipv6_dhcp || adapter.ipv6_dns.is_empty() {
            script.push_str(&format!(
                "netsh interface ipv6 set dnsservers name=\"{name}\" source=dhcp\r\n"
            ));
        } else {
            for (index, dns) in adapter.ipv6_dns.iter().enumerate() {
                if index == 0 {
                    script.push_str(&format!(
                        "netsh interface ipv6 set dnsservers name=\"{name}\" static {dns} primary validate=no\r\n"
                    ));
                } else {
                    script.push_str(&format!(
                        "netsh interface ipv6 add dnsservers name=\"{name}\" {dns} index={} validate=no\r\n",
                        index + 1
                    ));
                }
            }
        }
    }

    script.push_str("\r\necho [2/2] 正在刷新系统 DNS 解析缓存...\r\n");
    script.push_str("ipconfig /flushdns\r\n\r\n");
    script.push_str("echo ================================================================\r\n");
    script.push_str("echo 系统 DNS 设置已完全恢复初始状态。\r\n");
    script.push_str("echo ================================================================\r\n");
    script.push_str("pause\r\n");

    if let Some(parent) = output_path.parent() {
        if !parent.as_os_str().is_empty() {
            std::fs::create_dir_all(parent).map_err(|error| {
                PlatformError::message(format!("创建应急脚本目录失败: {error}"))
            })?;
        }
    }
    std::fs::write(output_path, script)
        .map_err(|error| PlatformError::message(format!("写入应急恢复脚本失败: {error}")))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn echo_escapes_cmd_metacharacters() {
        assert_eq!(batch_echo_text("a&b"), "a^&b");
        assert_eq!(batch_echo_text("100%"), "100%%");
        assert_eq!(batch_echo_text("x^y"), "x^^y");
        assert_eq!(batch_echo_text("(队)"), "^(队^)");
    }

    #[test]
    fn quoted_arg_doubles_percent_and_rejects_quotes() {
        assert_eq!(batch_quoted_arg("100%").unwrap(), "100%%");
        assert!(batch_quoted_arg("bad\"name").is_err());
        assert!(batch_quoted_arg("bad\nname").is_err());
    }

    #[test]
    fn script_contains_dhcp_and_static_branches() {
        let adapters = vec![
            AdapterState {
                id: "a".into(),
                name: "以太网".into(),
                ipv4_dns: vec!["8.8.8.8".into(), "1.1.1.1".into()],
                ipv6_dns: vec![],
                ipv4_dhcp: false,
                ipv6_dhcp: true,
                ..AdapterState::default()
            },
            AdapterState {
                id: "b".into(),
                name: "Wi-Fi 50%".into(),
                ipv4_dhcp: true,
                ipv6_dhcp: true,
                ..AdapterState::default()
            },
        ];
        let path = std::env::temp_dir()
            .join(format!("diting-restore-{}", std::process::id()))
            .join("restore-dns.bat");
        generate_restore_script(&adapters, &path).unwrap();
        let content = std::fs::read_to_string(&path).unwrap();
        assert!(content.contains("netsh interface ipv4 set dnsservers name=\"以太网\" static 8.8.8.8 primary validate=no"));
        assert!(content.contains(
            "netsh interface ipv4 add dnsservers name=\"以太网\" 1.1.1.1 index=2 validate=no"
        ));
        assert!(content.contains("netsh interface ipv6 set dnsservers name=\"以太网\" source=dhcp"));
        assert!(content.contains("name=\"Wi-Fi 50%%\""));
        assert!(content.contains("正在恢复适配器 [Wi-Fi 50%%]"));
        assert!(content.contains("ipconfig /flushdns"));
        assert!(content.contains("@echo off\r\n"));
        let _ = std::fs::remove_dir_all(path.parent().unwrap());
    }
}
