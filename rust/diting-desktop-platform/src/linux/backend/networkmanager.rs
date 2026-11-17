//! NetworkManager backend (`nmcli con mod` per active connection).

use diting_desktop_api::platform_types::{AdapterInfo, AdapterState};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::netutil::clean_adapter_state;

use super::interface_name_from_state;
use crate::linux::dnsstate::command_exists;

/// Points every active connection at the local loopback resolver.
pub(crate) async fn apply(
    executor: &dyn CommandExecutor,
    _adapters: &[AdapterInfo],
) -> PlatformResult<()> {
    let connections = active_connections(executor).await?;
    if connections.is_empty() {
        return Err(PlatformError::message(
            "未找到由 NetworkManager 管理的活动连接",
        ));
    }

    let mut applied: Vec<String> = Vec::new();
    for connection in &connections {
        if let Err(error) = modify_connection(
            executor,
            connection,
            &["127.0.0.1".to_string()],
            &["::1".to_string()],
            true,
        )
        .await
        {
            revert_connections(executor, &applied).await;
            return Err(error);
        }
        applied.push(connection.clone());
    }
    Ok(())
}

/// Restores each active connection from the matching snapshot.
pub(crate) async fn restore(
    executor: &dyn CommandExecutor,
    adapters: &[AdapterState],
) -> PlatformResult<()> {
    let connections = active_connections(executor).await?;

    let mut last_error: Option<PlatformError> = None;
    for connection in &connections {
        let mut ipv4_dns = Vec::new();
        let mut ipv6_dns = Vec::new();
        for raw in adapters {
            let adapter = clean_adapter_state(raw);
            if connection_matches_adapter(connection, &adapter) {
                ipv4_dns = adapter.ipv4_dns;
                ipv6_dns = adapter.ipv6_dns;
                break;
            }
        }
        if let Err(error) =
            modify_connection(executor, connection, &ipv4_dns, &ipv6_dns, false).await
        {
            last_error = Some(error);
        }
    }
    match last_error {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

/// Flushes caches through `resolvectl` when available; otherwise there is nothing to do.
pub(crate) async fn flush(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    if command_exists("resolvectl") {
        executor
            .run_checked("resolvectl", &["flush-caches"])
            .await
            .map(|_| ())?;
    }
    Ok(())
}

async fn active_connections(executor: &dyn CommandExecutor) -> PlatformResult<Vec<String>> {
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

    let mut connections = Vec::new();
    for line in output.text().lines() {
        let fields: Vec<&str> = line.split(':').collect();
        if fields.len() < 3 {
            continue;
        }
        let name = fields[0].trim();
        if name.is_empty() || name == "lo" {
            continue;
        }
        connections.push(name.to_string());
    }
    Ok(connections)
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

fn connection_matches_adapter(connection: &str, adapter: &AdapterState) -> bool {
    let name = interface_name_from_state(adapter);
    connection == name || connection.eq_ignore_ascii_case(&adapter.name)
}
