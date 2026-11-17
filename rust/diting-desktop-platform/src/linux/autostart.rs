//! XDG desktop-entry autostart (`~/.config/autostart/diting.desktop`).

use std::path::{Path, PathBuf};

use diting_desktop_api::platform_types::{
    AutoStartStatus, AUTO_START_MECHANISM_NONE, AUTO_START_MECHANISM_XDG,
};

use crate::error::{PlatformError, PlatformResult};
use crate::traits::AutoStartManager;

use super::files;

/// XDG autostart manager for the Linux desktop.
#[derive(Debug, Clone, Copy, Default)]
pub struct LinuxAutoStart;

impl LinuxAutoStart {
    pub fn new() -> Self {
        Self
    }
}

impl AutoStartManager for LinuxAutoStart {
    fn is_enabled(&self) -> bool {
        xdg_auto_start_present()
    }

    fn set_enabled(&self, enable: bool) -> PlatformResult<AutoStartStatus> {
        let path = desktop_file_path().ok_or_else(|| {
            PlatformError::message("无法获取用户配置目录 (HOME/XDG_CONFIG_HOME 未设置)")
        })?;

        if enable {
            let exe_path = std::env::current_exe()
                .map_err(|error| PlatformError::message(format!("获取执行路径失败: {error}")))?;
            if let Some(directory) = path.parent() {
                std::fs::create_dir_all(directory).map_err(|error| {
                    PlatformError::message(format!("创建自启目录失败: {error}"))
                })?;
            }
            let entry = format!(
                "[Desktop Entry]\nType=Application\nName=谛听 DNS\nExec={}\nHidden=false\nNoDisplay=false\nX-GNOME-Autostart-enabled=true\n",
                exec_value(&exe_path.to_string_lossy())
            );
            files::write_file_mode(&path, entry.as_bytes(), 0o644).map_err(|error| {
                PlatformError::message(format!("写入自启桌面条目失败: {error}"))
            })?;
            return Ok(AutoStartStatus {
                enabled: true,
                mechanism: AUTO_START_MECHANISM_XDG.to_string(),
                detail: "已写入 XDG 桌面登录自启条目，登录桌面后将自动运行。".to_string(),
            });
        }

        match std::fs::remove_file(&path) {
            Ok(()) => {}
            Err(error) if files::is_not_exist(&error) => {}
            Err(error) => {
                return Err(PlatformError::message(format!(
                    "移除自启桌面条目失败: {error}"
                )))
            }
        }
        Ok(AutoStartStatus {
            enabled: false,
            mechanism: AUTO_START_MECHANISM_NONE.to_string(),
            detail: "已移除 XDG 桌面登录自启条目。".to_string(),
        })
    }
}

/// Absolute XDG autostart entry path, or `None` when no home directory is known.
pub(crate) fn desktop_file_path() -> Option<PathBuf> {
    let config_dir = match std::env::var_os("XDG_CONFIG_HOME") {
        Some(value) if !value.is_empty() => PathBuf::from(value),
        _ => {
            let home = std::env::var_os("HOME").filter(|value| !value.is_empty())?;
            Path::new(&home).join(".config")
        }
    };
    Some(config_dir.join("autostart").join("diting.desktop"))
}

/// Whether the XDG entry exists and (when parseable) points at an existing executable.
pub(crate) fn xdg_auto_start_present() -> bool {
    let Some(path) = desktop_file_path() else {
        return false;
    };
    let Ok(content) = std::fs::read_to_string(path) else {
        return false;
    };
    // File existence alone would report an entry whose Exec no longer exists as enabled.
    let executable = parse_desktop_exec(&content);
    if executable.is_empty() {
        return true;
    }
    std::fs::metadata(executable)
        .map(|metadata| !metadata.is_dir())
        .unwrap_or(false)
}

/// Extracts the executable from an `Exec=` line (honoring quotes and backslash escapes).
pub(crate) fn parse_desktop_exec(content: &str) -> String {
    for line in content.split('\n') {
        let Some(value) = line.strip_prefix("Exec=") else {
            continue;
        };
        let value = value.trim();
        if value.is_empty() {
            return String::new();
        }
        if value.starts_with('"') {
            let mut executable = String::new();
            let mut escaped = false;
            for character in value.chars().skip(1) {
                if escaped {
                    executable.push(character);
                    escaped = false;
                    continue;
                }
                match character {
                    '\\' => escaped = true,
                    '"' => return executable,
                    other => executable.push(other),
                }
            }
            return executable;
        }
        return value.split_whitespace().next().unwrap_or("").to_string();
    }
    String::new()
}

/// Quotes an executable path following the Desktop Entry escaping rules.
fn exec_value(path: &str) -> String {
    let mut quoted = String::from("\"");
    for character in path.chars() {
        match character {
            '\\' | '"' | '`' | '$' => {
                quoted.push('\\');
                quoted.push(character);
            }
            '%' => quoted.push_str("%%"),
            other => quoted.push(other),
        }
    }
    quoted.push('"');
    quoted
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exec_line_parsers_handle_quotes_and_plain_paths() {
        assert_eq!(
            parse_desktop_exec("[Desktop Entry]\nExec=\"/opt/my app/diting\" --flag\n"),
            "/opt/my app/diting"
        );
        assert_eq!(
            parse_desktop_exec("Exec=/usr/bin/diting --flag\n"),
            "/usr/bin/diting"
        );
        assert_eq!(parse_desktop_exec("Name=no exec\n"), "");
    }

    #[test]
    fn exec_value_escapes_special_characters() {
        assert_eq!(exec_value("/opt/diting"), "\"/opt/diting\"");
        assert_eq!(exec_value("/opt/a b%d"), "\"/opt/a b%%d\"");
        assert_eq!(exec_value("/opt/a$b"), "\"/opt/a\\$b\"");
    }
}
