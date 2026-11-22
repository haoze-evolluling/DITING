use std::sync::Arc;
use std::time::Duration;

use async_trait::async_trait;
use diting_desktop_api::platform_types::{PortCheckResult, PortConflict};

use crate::error::PlatformResult;
use crate::exec::CommandExecutor;
use crate::ports::{are_addresses_available, is_only_loopback};
use crate::traits::PortChecker;

use super::portcheck_ics::stop_and_disable_shared_access;
use super::portcheck_native::check_port53_native;

pub struct WindowsPortChecker {
    executor: Arc<dyn CommandExecutor>,
}

impl WindowsPortChecker {
    pub fn new(executor: Arc<dyn CommandExecutor>) -> Self {
        Self { executor }
    }
}

pub(crate) fn evaluate_port_availability(
    sockets_free: bool,
    conflicts: Vec<PortConflict>,
    has_ics: bool,
    mut diagnostic: String,
    udp_addrs: &[String],
    tcp_addrs: &[String],
) -> PortCheckResult {
    let mut has_third_party_conflict = false;
    let mut has_self_listener = false;
    for conflict in &conflicts {
        if conflict.is_self {
            has_self_listener = true;
        } else if !conflict.is_ics {
            has_third_party_conflict = true;
        }
    }

    let mut available = false;
    let mut can_autofix = false;

    if sockets_free || has_self_listener {
        available = true;
    } else if has_ics && !has_third_party_conflict {
        can_autofix = true;
        if !is_only_loopback(udp_addrs, tcp_addrs) {
            diagnostic = format!(
                "当前启用了局域网共享监听 (0.0.0.0:53)，检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行并占用了 0.0.0.0:53。\n排查建议：点击【一键自动修复并启动】自动停止并禁用 ICS 服务，或关闭局域网共享模式降级为仅本机回环监听。\n{diagnostic}"
            );
        } else {
            diagnostic = format!(
                "53 端口套接字绑定失败。检测到 Windows 网络连接共享服务 (SharedAccess / ICS) 正在运行。\n排查建议：点击【一键自动修复并启动】自动停止并禁用 ICS 服务后重试。\n{diagnostic}"
            );
        }
    } else if has_ics && has_third_party_conflict {
        diagnostic = format!(
            "53 端口同时被 Windows 网络连接共享服务 (SharedAccess / ICS) 与第三方外部程序占用。\n排查建议：需先在任务管理器中关闭占用 53 端口的外部程序并停止 ICS 服务。\n{diagnostic}"
        );
    }

    PortCheckResult {
        available,
        conflicts,
        has_ics,
        can_autofix,
        diagnostic,
    }
}

async fn check_for_addresses(
    executor: &dyn CommandExecutor,
    udp_addrs: &[String],
    tcp_addrs: &[String],
) -> PlatformResult<PortCheckResult> {
    let (udp_addrs, tcp_addrs) = if udp_addrs.is_empty() && tcp_addrs.is_empty() {
        (
            vec!["127.0.0.1:53".to_string()],
            vec!["127.0.0.1:53".to_string()],
        )
    } else {
        (udp_addrs.to_vec(), tcp_addrs.to_vec())
    };

    let sockets_free = are_addresses_available(&udp_addrs, &tcp_addrs);
    let (conflicts, has_ics, diagnostic) =
        check_port53_native(executor, sockets_free, std::process::id()).await;
    Ok(evaluate_port_availability(
        sockets_free,
        conflicts,
        has_ics,
        diagnostic,
        &udp_addrs,
        &tcp_addrs,
    ))
}

#[async_trait]
impl PortChecker for WindowsPortChecker {
    async fn check_port53(&self) -> PlatformResult<PortCheckResult> {
        check_for_addresses(
            self.executor.as_ref(),
            &["127.0.0.1:53".to_string()],
            &["127.0.0.1:53".to_string()],
        )
        .await
    }

    async fn check_port53_for_addresses(
        &self,
        udp_addrs: &[String],
        tcp_addrs: &[String],
    ) -> PlatformResult<PortCheckResult> {
        check_for_addresses(self.executor.as_ref(), udp_addrs, tcp_addrs).await
    }

    async fn autofix_port53_for_addresses(
        &self,
        udp_addrs: &[String],
        tcp_addrs: &[String],
    ) -> PlatformResult<PortCheckResult> {
        stop_and_disable_shared_access().await?;
        tokio::time::sleep(Duration::from_millis(300)).await;
        check_for_addresses(self.executor.as_ref(), udp_addrs, tcp_addrs).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn conflict(pid: i32, is_ics: bool, is_self: bool) -> PortConflict {
        PortConflict {
            port: 53,
            protocol: "UDP".into(),
            local_address: "0.0.0.0:53".into(),
            pid,
            process_name: if is_ics {
                "svchost.exe".into()
            } else {
                "named.exe".into()
            },
            service_name: if is_ics {
                "SharedAccess".into()
            } else {
                String::new()
            },
            is_ics,
            is_self,
            diagnosis: String::new(),
        }
    }

    fn addresses(value: &str) -> Vec<String> {
        vec![value.to_string()]
    }

    #[test]
    fn free_sockets_are_available_even_with_ics() {
        let result = evaluate_port_availability(
            true,
            vec![conflict(1768, true, false)],
            true,
            "ics running".into(),
            &addresses("127.0.0.1:53"),
            &addresses("127.0.0.1:53"),
        );
        assert!(result.available);
        assert!(!result.can_autofix);
    }

    #[test]
    fn lan_bind_blocked_only_by_ics_is_autofixable() {
        let result = evaluate_port_availability(
            false,
            vec![conflict(1768, true, false)],
            true,
            "ics block".into(),
            &addresses("0.0.0.0:53"),
            &addresses("0.0.0.0:53"),
        );
        assert!(!result.available);
        assert!(result.can_autofix);
        assert!(result.diagnostic.contains("一键自动修复并启动"));
    }

    #[test]
    fn ics_plus_third_party_is_not_autofixable() {
        let result = evaluate_port_availability(
            false,
            vec![conflict(1768, true, false), conflict(9999, false, false)],
            true,
            "dual block".into(),
            &addresses("0.0.0.0:53"),
            &addresses("0.0.0.0:53"),
        );
        assert!(!result.available);
        assert!(!result.can_autofix);
        assert!(result.diagnostic.contains("第三方外部程序"));
    }

    #[test]
    fn third_party_alone_is_not_autofixable() {
        let result = evaluate_port_availability(
            false,
            vec![conflict(9999, false, false)],
            false,
            "third".into(),
            &addresses("127.0.0.1:53"),
            &addresses("127.0.0.1:53"),
        );
        assert!(!result.available);
        assert!(!result.can_autofix);
    }

    #[test]
    fn self_listener_counts_as_available() {
        let result = evaluate_port_availability(
            false,
            vec![conflict(1234, false, true)],
            false,
            "self listening".into(),
            &addresses("127.0.0.1:53"),
            &addresses("127.0.0.1:53"),
        );
        assert!(result.available);
        assert!(!result.can_autofix);
    }
}
