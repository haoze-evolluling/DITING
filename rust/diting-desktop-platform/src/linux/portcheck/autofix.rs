use std::path::Path;

use crate::error::{PlatformError, PlatformResult};
use crate::exec::CommandExecutor;
use crate::linux::dnsstate::{self, RESOLVED_DROP_FILE, RESOLVED_DROP_IN_CONTENT};
use crate::linux::files;

use super::owner::{is_systemd_resolved_process, systemd_resolved_pid};

pub(crate) async fn disable_resolved_stub_listener(
    executor: &dyn CommandExecutor,
) -> PlatformResult<()> {
    if !dnsstate::resolved_drop_in_supported() {
        return Err(PlatformError::message(
            "无法创建 /etc/systemd/resolved.conf.d 目录，请以 root 身份运行",
        ));
    }

    files::write_file_mode(
        Path::new(RESOLVED_DROP_FILE),
        RESOLVED_DROP_IN_CONTENT.as_bytes(),
        0o644,
    )
    .map_err(|error| PlatformError::message(format!("写入 {RESOLVED_DROP_FILE} 失败: {error}")))?;

    if let Err(error) = executor
        .run_checked("systemctl", &["restart", "systemd-resolved"])
        .await
    {
        if let Err(fallback) = stop_resolved_stub_process(executor).await {
            return Err(PlatformError::message(format!(
                "重启 systemd-resolved 失败 ({error})，且回退停止 stub 亦失败: {fallback}（已写入 {RESOLVED_DROP_FILE}，卸载谛听后请手动删除）"
            )));
        }
    }
    Ok(())
}

async fn stop_resolved_stub_process(executor: &dyn CommandExecutor) -> PlatformResult<()> {
    let pid = systemd_resolved_pid();
    if pid == 0 {
        return Err(PlatformError::message(
            "未能定位 systemd-resolved 进程，无法终止 stub 监听器",
        ));
    }
    if !is_systemd_resolved_process(pid) {
        return Err(PlatformError::message(format!(
            "PID {pid} 不是 systemd-resolved 进程，拒绝终止"
        )));
    }
    let pid = pid.to_string();
    executor
        .run_checked("kill", &["-TERM", &pid])
        .await
        .map(|_| ())
}
