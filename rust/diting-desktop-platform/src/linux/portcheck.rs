mod autofix;
mod owner;
mod proc;

use std::collections::HashSet;
use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_api::platform_types::{PortCheckResult, PortConflict};

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::ports::{are_addresses_available, is_only_loopback};
use crate::traits::PortChecker;

use owner::{
    is_resolved_stub_address, is_systemd_resolved_process, process_name, socket_inode_owners,
    systemd_resolved_pid,
};
use proc::collect_port53_sockets;

pub(crate) fn collect_port53_sockets_for_openwrt() -> std::io::Result<Vec<proc::ProcSocket>> {
    collect_port53_sockets()
}

pub(crate) fn socket_inode_owners_for_openwrt() -> std::collections::HashMap<u64, i32> {
    socket_inode_owners()
}

pub(crate) fn process_name_for_openwrt(pid: i32) -> String {
    process_name(pid)
}

const DEFAULT_PORT53_ADDRESS: &str = "127.0.0.1:53";

pub struct LinuxPortChecker {
    executor: Arc<dyn CommandExecutor>,
}

impl LinuxPortChecker {
    pub fn new(executor: Arc<dyn CommandExecutor>) -> Self {
        Self { executor }
    }
}

#[async_trait]
impl PortChecker for LinuxPortChecker {
    async fn check_port53(&self) -> PlatformResult<PortCheckResult> {
        self.check_port53_for_addresses(
            &[DEFAULT_PORT53_ADDRESS.to_string()],
            &[DEFAULT_PORT53_ADDRESS.to_string()],
        )
        .await
    }

    async fn check_port53_for_addresses(
        &self,
        udp_addrs: &[String],
        tcp_addrs: &[String],
    ) -> PlatformResult<PortCheckResult> {
        let (udp_addrs, tcp_addrs) = with_default_addresses(udp_addrs, tcp_addrs);
        let sockets_free = are_addresses_available(&udp_addrs, &tcp_addrs);

        match inspect_port53_listeners() {
            Ok((conflicts, has_stub, diagnostic)) => Ok(evaluate_linux_port_availability(
                sockets_free,
                &conflicts,
                has_stub,
                diagnostic,
                &udp_addrs,
                &tcp_addrs,
            )),
            Err(error) => Ok(PortCheckResult {
                available: sockets_free,
                conflicts: Vec::new(),
                has_ics: false,
                can_autofix: false,
                diagnostic: format!(
                    "53 端口套接字绑定探测: {sockets_free} (/proc 诊断失败: {error})"
                ),
            }),
        }
    }

    async fn autofix_port53_for_addresses(
        &self,
        udp_addrs: &[String],
        tcp_addrs: &[String],
    ) -> PlatformResult<PortCheckResult> {
        let (udp_addrs, tcp_addrs) = with_default_addresses(udp_addrs, tcp_addrs);
        let before = self
            .check_port53_for_addresses(&udp_addrs, &tcp_addrs)
            .await?;
        if before.available {
            return Ok(before);
        }
        if !before.has_ics {
            return Err(PlatformError::message(
                "检测到第三方程序占用 53 端口，无法自动修复，请手动停止相关进程",
            ));
        }

        if let Err(error) = autofix::disable_resolved_stub_listener(self.executor.as_ref()).await {
            return Err(PlatformError::message(format!(
                "自动修复 systemd-resolved stub 监听失败: {error}"
            )));
        }

        let mut after = self
            .check_port53_for_addresses(&udp_addrs, &tcp_addrs)
            .await?;
        if after.available {
            after.diagnostic = format!(
                "已成功关闭 systemd-resolved 的 stub 监听器，53 端口现已可用。\n{}",
                after.diagnostic
            );
            return Ok(after);
        }
        Err(PlatformError::message(
            "已关闭 systemd-resolved stub 监听器，但 53 端口仍不可用，请查看诊断信息",
        ))
    }
}

fn with_default_addresses(
    udp_addrs: &[String],
    tcp_addrs: &[String],
) -> (Vec<String>, Vec<String>) {
    if udp_addrs.is_empty() && tcp_addrs.is_empty() {
        (
            vec![DEFAULT_PORT53_ADDRESS.to_string()],
            vec![DEFAULT_PORT53_ADDRESS.to_string()],
        )
    } else {
        (udp_addrs.to_vec(), tcp_addrs.to_vec())
    }
}

fn inspect_port53_listeners() -> PlatformResult<(Vec<PortConflict>, bool, String)> {
    let sockets = collect_port53_sockets().map_err(PlatformError::from)?;
    if sockets.is_empty() {
        return Ok((Vec::new(), false, "53 端口当前空闲且可用。".to_string()));
    }

    let owners = socket_inode_owners();
    let self_pid = std::process::id() as i32;
    let resolved_pid = systemd_resolved_pid();

    let mut conflicts = Vec::new();
    let mut diagnostic_lines = Vec::new();
    let mut seen = HashSet::new();
    let mut has_stub = false;

    for socket in sockets {
        let key = format!("{}|{}", socket.protocol, socket.local_address);
        if !seen.insert(key) {
            continue;
        }

        let pid = owners.get(&socket.inode).copied().unwrap_or(0);
        let name = process_name(pid);
        let is_self = pid == self_pid;
        let is_stub = is_resolved_stub_address(&socket.local_address)
            || (resolved_pid != 0 && pid == resolved_pid)
            || is_systemd_resolved_process(pid);

        let mut conflict = PortConflict {
            port: 53,
            protocol: socket.protocol.clone(),
            local_address: socket.local_address.clone(),
            pid,
            process_name: name.clone(),
            service_name: String::new(),
            is_ics: is_stub,
            is_self,
            diagnosis: String::new(),
        };

        if is_self {
            conflict.diagnosis = "谛听 (DITING) 核心服务监听中。".to_string();
            diagnostic_lines.push(format!(
                "谛听 (DITING) 核心服务正在监听 {}",
                socket.local_address
            ));
        } else if is_stub {
            has_stub = true;
            conflict.service_name = "systemd-resolved".to_string();
            conflict.diagnosis =
                "systemd-resolved 的 stub 监听器占用了该地址，会阻止本地 DNS 代理绑定 127.0.0.53:53。"
                    .to_string();
            diagnostic_lines.push(format!(
                "检测到 systemd-resolved stub 监听器占用 {} (PID: {})。systemd-resolved 默认在 127.0.0.53:53 与 127.0.0.54:53 上提供本地存根解析。",
                socket.local_address, pid
            ));
        } else if pid != 0 {
            conflict.diagnosis =
                format!("被外部进程 {name} (PID: {pid}) 占用，需先停止该进程再启动谛听 DNS 服务。");
            diagnostic_lines.push(format!(
                "外部程序 {name} (PID: {pid}) 正在占用 {}。",
                socket.local_address
            ));
        } else {
            conflict.diagnosis =
                "占用进程无法定位（可能属于其他用户或已退出），请使用 sudo ss -lunpt 进一步排查。"
                    .to_string();
            diagnostic_lines.push(format!("{} 被未知进程占用。", socket.local_address));
        }

        conflicts.push(conflict);
    }

    conflicts.sort_by(|left, right| {
        left.protocol
            .cmp(&right.protocol)
            .then_with(|| left.local_address.cmp(&right.local_address))
    });

    Ok((conflicts, has_stub, diagnostic_lines.join("\n")))
}

fn evaluate_linux_port_availability(
    sockets_free: bool,
    conflicts: &[PortConflict],
    has_stub: bool,
    diagnostic: String,
    udp_addrs: &[String],
    tcp_addrs: &[String],
) -> PortCheckResult {
    let mut has_third_party = false;
    let mut has_self_listener = false;
    for conflict in conflicts {
        if conflict.is_self {
            has_self_listener = true;
        } else if !conflict.is_ics {
            has_third_party = true;
        }
    }

    let mut diagnostic = diagnostic;
    let (available, can_autofix) = if sockets_free || has_self_listener {
        (true, false)
    } else if has_stub && !has_third_party {
        if !is_only_loopback(udp_addrs, tcp_addrs) {
            diagnostic = format!(
                "当前启用了局域网共享监听 (0.0.0.0:53)，但 systemd-resolved 的 stub 监听器占用了本机 53 端口。\n排查建议：点击【一键自动修复并启动】关闭 systemd-resolved 的 DNSStubListener 并重启该服务，或关闭局域网共享模式降级为仅本机回环监听。\n{diagnostic}"
            );
        } else {
            diagnostic = format!(
                "53 端口套接字绑定失败，systemd-resolved 的 stub 监听器正在运行。\n排查建议：点击【一键自动修复并启动】写入 /etc/systemd/resolved.conf.d/diting.conf 并设置 DNSStubListener=no，随后重启 systemd-resolved。\n{diagnostic}"
            );
        }
        (false, true)
    } else if has_stub && has_third_party {
        diagnostic = format!(
            "53 端口同时被 systemd-resolved 与第三方外部程序占用。\n排查建议：请先用 sudo ss -lunpt | grep :53 定位并停止外部程序，再处理 systemd-resolved。\n{diagnostic}"
        );
        (false, false)
    } else {
        (false, false)
    };

    PortCheckResult {
        available,
        conflicts: conflicts.to_vec(),
        has_ics: has_stub,
        can_autofix,
        diagnostic,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conflict(is_self: bool, is_ics: bool) -> PortConflict {
        PortConflict {
            is_self,
            is_ics,
            ..PortConflict::default()
        }
    }

    #[test]
    fn stub_only_allows_autofix_for_loopback_listeners() {
        let result = evaluate_linux_port_availability(
            false,
            &[conflict(false, true)],
            true,
            "stub".to_string(),
            &["127.0.0.1:53".to_string()],
            &["127.0.0.1:53".to_string()],
        );
        assert!(!result.available);
        assert!(result.can_autofix);
        assert!(result.has_ics);
        assert!(result.diagnostic.contains("DNSStubListener=no"));
    }

    #[test]
    fn third_party_conflict_blocks_autofix() {
        let result = evaluate_linux_port_availability(
            false,
            &[conflict(false, false)],
            false,
            "external".to_string(),
            &["127.0.0.1:53".to_string()],
            &["127.0.0.1:53".to_string()],
        );
        assert!(!result.available);
        assert!(!result.can_autofix);
    }

    #[test]
    fn self_listener_counts_as_available() {
        let result = evaluate_linux_port_availability(
            false,
            &[conflict(true, false)],
            false,
            "self".to_string(),
            &["127.0.0.1:53".to_string()],
            &["127.0.0.1:53".to_string()],
        );
        assert!(result.available);
        assert!(!result.can_autofix);
    }

    #[test]
    fn lan_listening_stub_gets_shared_mode_hint() {
        let result = evaluate_linux_port_availability(
            false,
            &[conflict(false, true)],
            true,
            "stub".to_string(),
            &["0.0.0.0:53".to_string()],
            &["0.0.0.0:53".to_string()],
        );
        assert!(result.diagnostic.contains("局域网共享监听"));
        assert!(result.can_autofix);
    }
}
