use diting_desktop_api::platform_types::{AdapterInfo, AdapterState};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::netutil::clean_adapter_state;

use super::{interface_name_from_adapter, interface_name_from_state};
use crate::linux::dnsstate::{command_exists, split_terse_fields};

/// NetworkManager 的活动连接。连接名与网卡设备名通常不同（例如
/// "Wired connection 1" 对应设备 "eth0"），两者都必须保留：`nmcli con mod`
/// 按连接名操作，而快照还原必须按设备名与网卡匹配。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ActiveConnection {
    pub name: String,
    pub device: String,
}

pub(crate) async fn apply(
    executor: &dyn CommandExecutor,
    adapters: &[AdapterInfo],
) -> PlatformResult<()> {
    let connections = active_connections(executor).await?;
    if connections.is_empty() {
        return Err(PlatformError::message(
            "未找到由 NetworkManager 管理的活动连接",
        ));
    }

    let targets = select_connections(&connections, adapters);
    if targets.is_empty() {
        return Err(PlatformError::message(format!(
            "未找到与所选网卡匹配的 NetworkManager 活动连接（设备: {}）",
            adapter_names(adapters).join(", ")
        )));
    }

    let mut applied: Vec<String> = Vec::new();
    for connection in &targets {
        if let Err(error) = modify_connection(
            executor,
            &connection.name,
            &["127.0.0.1".to_string()],
            &["::1".to_string()],
            true,
        )
        .await
        {
            revert_connections(executor, &applied).await;
            return Err(error);
        }
        applied.push(connection.name.clone());
    }
    Ok(())
}

pub(crate) async fn restore(
    executor: &dyn CommandExecutor,
    adapters: &[AdapterState],
) -> PlatformResult<()> {
    let connections = active_connections(executor).await?;

    let mut last_error: Option<PlatformError> = None;
    for connection in &connections {
        let Some(adapter) = matching_adapter(connection, adapters) else {
            continue;
        };
        if let Err(error) = modify_connection(
            executor,
            &connection.name,
            &adapter.ipv4_dns,
            &adapter.ipv6_dns,
            false,
        )
        .await
        {
            last_error = Some(error);
        }
    }
    match last_error {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

pub(crate) async fn flush(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    if command_exists("resolvectl") {
        // 尽力而为：缓存刷新失败不影响 DNS 接管是否成功。
        let _ = executor.run("resolvectl", &["flush-caches"]).await;
    }
    Ok(())
}

async fn active_connections(
    executor: &dyn CommandExecutor,
) -> PlatformResult<Vec<ActiveConnection>> {
    let output = executor
        .run(
            "nmcli",
            &["-t", "-f", "NAME,DEVICE,STATE", "con", "show", "--active"],
        )
        .await
        .map_err(|error| {
            PlatformError::message(format!("查询 NetworkManager 活动连接失败: {error}"))
        })?;
    if !output.success {
        return Err(PlatformError::message(format!(
            "查询 NetworkManager 活动连接失败: {}",
            output.text()
        )));
    }
    Ok(parse_active_connections(&output.text()))
}

pub(crate) fn parse_active_connections(output: &str) -> Vec<ActiveConnection> {
    let mut connections = Vec::new();
    for line in output.lines() {
        let fields = split_terse_fields(line);
        if fields.len() < 3 {
            continue;
        }
        let name = fields[0].trim().to_string();
        let device = fields[1].trim().to_string();
        if name.is_empty() || device.is_empty() || device == "lo" {
            continue;
        }
        let connection = ActiveConnection { name, device };
        if !connections.contains(&connection) {
            connections.push(connection);
        }
    }
    connections
}

fn select_connections(
    connections: &[ActiveConnection],
    adapters: &[AdapterInfo],
) -> Vec<ActiveConnection> {
    connections
        .iter()
        .filter(|connection| {
            adapters.iter().any(|adapter| {
                let iface = interface_name_from_adapter(adapter);
                !iface.is_empty() && interface_matches(connection, iface)
            })
        })
        .cloned()
        .collect()
}

fn matching_adapter(
    connection: &ActiveConnection,
    adapters: &[AdapterState],
) -> Option<AdapterState> {
    for raw in adapters {
        let adapter = clean_adapter_state(raw);
        let iface = interface_name_from_state(&adapter);
        if iface.is_empty() {
            continue;
        }
        if interface_matches(connection, iface) {
            return Some(adapter);
        }
    }
    None
}

fn interface_matches(connection: &ActiveConnection, iface: &str) -> bool {
    connection.device.eq_ignore_ascii_case(iface) || connection.name.eq_ignore_ascii_case(iface)
}

fn adapter_names(adapters: &[AdapterInfo]) -> Vec<String> {
    adapters
        .iter()
        .map(|adapter| {
            let iface = interface_name_from_adapter(adapter);
            if iface.is_empty() {
                adapter.name.clone()
            } else {
                iface.to_string()
            }
        })
        .collect()
}

async fn modify_connection(
    executor: &dyn CommandExecutor,
    connection: &str,
    ipv4_dns: &[String],
    ipv6_dns: &[String],
    ignore_auto: bool,
) -> PlatformResult<()> {
    let ipv4_arg = ipv4_dns.join(",");
    let ipv6_arg = ipv6_dns.join(",");
    let ignore_arg = if ignore_auto { "yes" } else { "no" };

    let args = [
        "con",
        "mod",
        connection,
        "ipv4.dns",
        &ipv4_arg,
        "ipv6.dns",
        &ipv6_arg,
        "ipv4.ignore-auto-dns",
        ignore_arg,
        "ipv6.ignore-auto-dns",
        ignore_arg,
    ];
    executor
        .run_checked("nmcli", &args)
        .await
        .map_err(|error| {
            PlatformError::message(format!("修改连接 [{connection}] 的 DNS 设置失败: {error}"))
        })?;

    executor
        .run_checked("nmcli", &["con", "up", connection])
        .await
        .map_err(|error| {
            PlatformError::message(format!("重新激活连接 [{connection}] 失败: {error}"))
        })?;
    Ok(())
}

async fn revert_connections(executor: &dyn CommandExecutor, connections: &[String]) {
    for connection in connections {
        let _ = modify_connection(executor, connection, &[], &[], false).await;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn active_connections_keep_name_and_device() {
        let output = "Wired connection 1:eth0:activated\n\
                      Office\\: floor 2:wlan0:activated\n\
                      lo:lo:activated\n\
                      bad-row\n";
        let connections = parse_active_connections(output);
        assert_eq!(
            connections,
            vec![
                ActiveConnection {
                    name: "Wired connection 1".to_string(),
                    device: "eth0".to_string()
                },
                ActiveConnection {
                    name: "Office: floor 2".to_string(),
                    device: "wlan0".to_string()
                }
            ]
        );
    }

    #[test]
    fn selection_matches_device_not_only_connection_name() {
        let connections = vec![ActiveConnection {
            name: "Wired connection 1".to_string(),
            device: "eth0".to_string(),
        }];
        let adapter = AdapterInfo {
            id: "eth0".to_string(),
            name: "eth0".to_string(),
            ..AdapterInfo::default()
        };
        assert_eq!(select_connections(&connections, &[adapter]).len(), 1);
    }

    #[test]
    fn restore_skips_connections_without_matching_adapter() {
        let connection = ActiveConnection {
            name: "Docker bridge".to_string(),
            device: "docker0".to_string(),
        };
        let adapter = AdapterState {
            id: "eth0".to_string(),
            name: "eth0".to_string(),
            ..AdapterState::default()
        };
        assert!(matching_adapter(&connection, &[adapter]).is_none());
    }

    #[test]
    fn name_matching_is_case_insensitive_fallback() {
        let connection = ActiveConnection {
            name: "ETH0".to_string(),
            device: "eth0".to_string(),
        };
        assert!(interface_matches(&connection, "eth0"));
    }
}
