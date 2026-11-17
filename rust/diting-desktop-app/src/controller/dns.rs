//! DNS listener lifecycle (`/api/v1/dns/start|stop`).

use diting_desktop_api::platform_types::PortCheckResult;

use crate::controller::{effective_listen_addresses, ControllerError};
use crate::AppRuntime;

fn needs_port53(udp: &[String], tcp: &[String]) -> bool {
    udp.iter()
        .chain(tcp.iter())
        .any(|address| address.ends_with(":53"))
}

fn fallback_conflict(message: impl Into<String>) -> ControllerError {
    ControllerError::conflict(PortCheckResult {
        available: false,
        diagnostic: message.into(),
        ..PortCheckResult::default()
    })
}

impl AppRuntime {
    /// Starts DNS, refusing to bind when an occupied 53 port would silently split traffic.
    pub async fn start_dns_checked(&self) -> Result<(), ControllerError> {
        if self.is_dns_running() {
            return Ok(());
        }
        let config = self.config();
        let (udp, tcp) = effective_listen_addresses(&config.dns);
        let checker = self
            .platform()
            .and_then(|platform| platform.port_checker.clone());

        if needs_port53(&udp, &tcp) {
            if let Some(checker) = checker.clone() {
                match checker.check_port53_for_addresses(&udp, &tcp).await {
                    Ok(result) if !result.available => {
                        return Err(ControllerError::conflict(result));
                    }
                    Ok(_) => {}
                    Err(error) => {
                        return Err(fallback_conflict(format!("端口检测失败: {error}")));
                    }
                }
            }
        }

        if let Err(error) = self.start_dns().await {
            if let Some(checker) = checker {
                if let Ok(result) = checker.check_port53_for_addresses(&udp, &tcp).await {
                    return Err(ControllerError::conflict(result));
                }
            }
            return Err(ControllerError::new(format!(
                "启动 DNS 监听器失败: {error}"
            )));
        }
        Ok(())
    }

    /// Stops DNS, restoring system DNS first so the host never loses resolution.
    pub async fn stop_dns_checked(&self) -> Result<(), ControllerError> {
        if let Some(platform) = self.platform() {
            if let Some(manager) = platform.dns_manager.clone() {
                if manager.is_takeover_active() {
                    let _ = manager.restore().await;
                }
            }
        }
        self.stop_dns().await;
        Ok(())
    }
}
