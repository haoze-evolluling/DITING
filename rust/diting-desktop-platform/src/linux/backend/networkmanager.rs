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

/// 连接禁用 IPv6（`ipv6.method=disabled/ignore`）时，写入 `ipv6.dns`
/// 会让整条 `nmcli con mod` 失败，因此按连接的 IPv6 方式动态拼参数。
async fn supports_ipv6(executor: &dyn CommandExecutor, connection: &str) -> bool {
    match executor
        .run(
            "nmcli",
            &["-t", "-f", "ipv6.method", "con", "show", connection],
        )
        .await
    {
        Ok(output) if output.success => {
            let method = parse_nmcli_property(&output.text(), "ipv6.method").unwrap_or_default();
            !method.eq_ignore_ascii_case("disabled") && !method.eq_ignore_ascii_case("ignore")
        }
        _ => true,
    }
}

pub(crate) fn parse_nmcli_property(output: &str, key: &str) -> Option<String> {
    output.lines().find_map(|line| {
        let (name, value) = line.split_once(':')?;
        (name.trim() == key).then(|| value.trim().to_string())
    })
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

    let mut args: Vec<String> = vec![
        "con".to_string(),
        "mod".to_string(),
        connection.to_string(),
        "ipv4.dns".to_string(),
        ipv4_arg,
        "ipv4.ignore-auto-dns".to_string(),
        ignore_arg.to_string(),
    ];
    if supports_ipv6(executor, connection).await {
        args.push("ipv6.dns".to_string());
        args.push(ipv6_arg);
        args.push("ipv6.ignore-auto-dns".to_string());
        args.push(ignore_arg.to_string());
    }
    let arg_refs: Vec<&str> = args.iter().map(String::as_str).collect();
    executor
        .run_checked("nmcli", &arg_refs)
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
    fn nmcli_properties_are_parsed_by_key() {
        let output = "ipv6.method:disabled\nipv4.method:manual\n";
        assert_eq!(
            parse_nmcli_property(output, "ipv6.method"),
            Some("disabled".to_string())
        );
        assert_eq!(
            parse_nmcli_property(output, "ipv4.method"),
            Some("manual".to_string())
        );
        assert_eq!(parse_nmcli_property(output, "ipv6.dns"), None);
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
