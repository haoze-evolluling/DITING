use std::process::Stdio;
use std::time::Duration;

use tokio::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RunError {
    NotFound,
    Timeout,
    Failed(String),
}

impl RunError {
    pub fn message(&self, program: &str) -> String {
        match self {
            Self::NotFound => format!("未找到系统命令 {program}"),
            Self::Timeout => format!("{program} 执行超时"),
            Self::Failed(error) => format!("{program} 执行失败: {error}"),
        }
    }
}

/// 运行系统诊断命令，合并 stdout / stderr；超时会强制结束进程。
pub async fn run(program: &str, args: &[String], timeout: Duration) -> Result<String, RunError> {
    let mut command = Command::new(program);
    command
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    #[cfg(windows)]
    {
        // 服务以 SYSTEM 身份运行，避免诊断命令弹出控制台窗口。
        command.creation_flags(0x0800_0000);
    }

    let child = command.spawn().map_err(|error| {
        if error.kind() == std::io::ErrorKind::NotFound {
            RunError::NotFound
        } else {
            RunError::Failed(error.to_string())
        }
    })?;

    match tokio::time::timeout(timeout, child.wait_with_output()).await {
        Ok(Ok(output)) => {
            let stdout = decode(&output.stdout);
            let stderr = decode(&output.stderr);
            Ok(format!("{stdout}\n{stderr}").trim().to_string())
        }
        Ok(Err(error)) => Err(RunError::Failed(error.to_string())),
        Err(_) => Err(RunError::Timeout),
    }
}

/// 系统命令在中文 Windows 上按 OEM 代码页输出（GBK），需要先尝试 UTF-8 再回退。
fn decode(bytes: &[u8]) -> String {
    #[cfg(windows)]
    if let Ok(text) = std::str::from_utf8(bytes) {
        return text.to_string();
    }
    #[cfg(windows)]
    {
        let (text, _, _) = encoding_rs::GBK.decode(bytes);
        return text.into_owned();
    }
    #[cfg(not(windows))]
    String::from_utf8_lossy(bytes).into_owned()
}
