use std::collections::HashSet;
use std::sync::Arc;

use async_trait::async_trait;
use diting_desktop_api::platform_types::{PortCheckResult, PortConflict};

use crate::error::{PlatformError, PlatformResult};
use crate::ports::are_addresses_available;
use crate::traits::{DnsManager, PortChecker};

use super::super::portcheck::{
    collect_port53_sockets_for_openwrt, process_name_for_openwrt, socket_inode_owners_for_openwrt,
};

const DEFAULT_PORT53_ADDRESS: &str = "0.0.0.0:53";

pub struct OpenWrtPortChecker {
    dns_manager: Arc<dyn DnsManager>,
}

impl OpenWrtPortChecker {
    pub fn new(dns_manager: Arc<dyn DnsManager>) -> Self {
        Self { dns_manager }
    }
}

#[async_trait]
impl PortChecker for OpenWrtPortChecker {
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
        let (udp_addrs, tcp_addrs) = with_defaults(udp_addrs, tcp_addrs);
        let sockets_free = are_addresses_available(&udp_addrs, &tcp_addrs);
        match inspect_openwrt_port53() {
            Ok((conflicts, has_dnsmasq, diagnostic)) => Ok(evaluate_openwrt_availability(
                sockets_free,
                &conflicts,
                has_dnsmasq,
                diagnostic,
            )),
            Err(error) => Ok(PortCheckResult {
                available: sockets_free,
                conflicts: Vec::new(),
                has_ics: false,
                can_autofix: false,
                diagnostic: format!("53 端口套接字探测: {sockets_free} (/proc 诊断异常: {error})"),
            }),
        }
    }

    async fn autofix_port53_for_addresses(
        &self,
        udp_addrs: &[String],
        tcp_addrs: &[String],
    ) -> PlatformResult<PortCheckResult> {
        let before = self
            .check_port53_for_addresses(udp_addrs, tcp_addrs)
            .await?;
        if before.available {
            return Ok(before);
        }
        if !before.can_autofix {
            return Err(PlatformError::message(
                "检测到非 dnsmasq 的第三方程序占用 53 端口，请先在 OpenWrt 中停止冲突服务（如 AdGuardHome / SmartDNS）",
            ));
        }
        self.dns_manager.takeover(&[]).await?;
        let mut after = self
            .check_port53_for_addresses(udp_addrs, tcp_addrs)
            .await?;
        if after.available {
            after.diagnostic = format!(
                "已通过 UCI 将 OpenWrt dnsmasq 迁移至辅端口，53 端口现已释放。\n{}",
                after.diagnostic
            );
            return Ok(after);
        }
        Err(PlatformError::message(
            "已调整 dnsmasq 端口，但 53 端口仍被占用，请查看诊断详情",
        ))
    }
}

fn with_defaults(udp: &[String], tcp: &[String]) -> (Vec<String>, Vec<String>) {
    if udp.is_empty() && tcp.is_empty() {
        (
            vec![DEFAULT_PORT53_ADDRESS.to_string()],
            vec![DEFAULT_PORT53_ADDRESS.to_string()],
        )
    } else {
        (udp.to_vec(), tcp.to_vec())
    }
}

fn inspect_openwrt_port53() -> PlatformResult<(Vec<PortConflict>, bool, String)> {
    let sockets = collect_port53_sockets_for_openwrt().map_err(PlatformError::from)?;
    if sockets.is_empty() {
        return Ok((Vec::new(), false, "53 端口当前空闲且可用。".to_string()));
    }

    let owners = socket_inode_owners_for_openwrt();
    let self_pid = std::process::id() as i32;
    let mut conflicts = Vec::new();
    let mut lines = Vec::new();
    let mut seen = HashSet::new();
    let mut has_dnsmasq = false;

    for socket in sockets {
        let key = format!("{}|{}", socket.protocol, socket.local_address);
        if !seen.insert(key) {
            continue;
        }
        let pid = owners.get(&socket.inode).copied().unwrap_or(0);
        let name = process_name_for_openwrt(pid);
        let is_self = pid == self_pid;
        let is_dnsmasq = name.eq_ignore_ascii_case("dnsmasq");

        let mut conflict = PortConflict {
            port: 53,
            protocol: socket.protocol.clone(),
            local_address: socket.local_address.clone(),
            pid,
            process_name: name.clone(),
            service_name: if is_dnsmasq {
                "dnsmasq".to_string()
            } else {
                String::new()
            },
            is_ics: is_dnsmasq,
            is_self,
            diagnosis: String::new(),
        };

        if is_self {
            conflict.diagnosis = "谛听 (DITING) 核心服务监听中。".to_string();
            lines.push(format!("谛听正在监听 {}", socket.local_address));
        } else if is_dnsmasq {
            has_dnsmasq = true;
            conflict.diagnosis =
                "OpenWrt 原生 dnsmasq 默认监听 53 端口，可通过路由器 DNS 接管自动迁移至辅端口。"
                    .to_string();
            lines.push(format!(
                "检测到 OpenWrt dnsmasq 监听 {} (PID: {})。",
                socket.local_address, pid
            ));
        } else if pid != 0 {
            conflict.diagnosis =
                format!("外部程序 {name} (PID: {pid}) 占用 53 端口，请先停用或修改其端口。");
            lines.push(format!(
                "外部进程 {name} (PID: {pid}) 占用 {}。",
                socket.local_address
            ));
        } else {
            conflict.diagnosis =
                "未知进程占用 53 端口，可执行 netstat -tulnp | grep :53 排查。".to_string();
            lines.push(format!("{} 被未知进程占用。", socket.local_address));
        }
        conflicts.push(conflict);
    }
    Ok((conflicts, has_dnsmasq, lines.join("\n")))
}

pub(crate) fn evaluate_openwrt_availability(
    sockets_free: bool,
    conflicts: &[PortConflict],
    has_dnsmasq: bool,
    mut diagnostic: String,
) -> PortCheckResult {
    let mut has_third_party = false;
    let mut has_self = false;
    for conflict in conflicts {
        if conflict.is_self {
            has_self = true;
        } else if !conflict.is_ics {
            has_third_party = true;
        }
    }

    let (available, can_autofix) = if sockets_free || has_self {
        (true, false)
    } else if has_dnsmasq && !has_third_party {
        diagnostic = format!(
            "OpenWrt 原生 dnsmasq 当前占用 53 端口。\n建议：开启「路由器 DNS 接管」或点击【一键自动修复并启动】，系统会自动将 dnsmasq 迁移至辅端口并保留 DHCP 与 .lan 解析。\n{diagnostic}"
        );
        (false, true)
    } else {
        (false, false)
    };

    PortCheckResult {
        available,
        conflicts: conflicts.to_vec(),
        has_ics: has_dnsmasq,
        can_autofix,
        diagnostic,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dnsmasq_conflict_is_autofixable_when_alone() {
        let dnsmasq = PortConflict {
            process_name: "dnsmasq".into(),
            is_ics: true,
            ..PortConflict::default()
        };
        let res = evaluate_openwrt_availability(false, &[dnsmasq], true, "dnsmasq".into());
        assert!(!res.available);
        assert!(res.can_autofix);
        assert!(res.has_ics);
    }
}
