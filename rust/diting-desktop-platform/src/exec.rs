//! System command execution.
//!
//! Nearly every Windows takeover step is a `netsh`/`sc`/`powershell` invocation and the Linux
//! backends shell out to `resolvectl`, `nmcli` and firewall tools. The executor exists so tests can
//! swap in a recorder and so a missing tool is reported as one failed step, not a panic.

use std::process::Stdio;
use std::time::Duration;

use async_trait::async_trait;
use tokio::process::Command;

use crate::error::{PlatformError, PlatformResult};

/// Combined stdout/stderr plus the exit status.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct CommandOutput {
    pub stdout: Vec<u8>,
    pub status: Option<i32>,
    pub success: bool,
}

impl CommandOutput {
    pub fn text(&self) -> String {
        String::from_utf8_lossy(&self.stdout).trim().to_string()
    }
}

/// Runs external programs. Production uses [`SystemExecutor`]; tests use a recorder.
#[async_trait]
pub trait CommandExecutor: Send + Sync {
    async fn run(&self, program: &str, args: &[&str]) -> PlatformResult<CommandOutput>;

    /// Runs a command and rejects a non-zero exit status with combined output as the message.
    async fn run_checked(&self, program: &str, args: &[&str]) -> PlatformResult<String> {
        let output = self.run(program, args).await?;
        if output.success {
            Ok(output.text())
        } else {
            Err(PlatformError::message(format!(
                "{program} {} 失败: {}",
                args.join(" "),
                output.text()
            )))
        }
    }
}

/// Production executor: inherits the service environment, captures combined output.
#[derive(Debug, Clone, Default)]
pub struct SystemExecutor {
    timeout: Option<Duration>,
}

impl SystemExecutor {
    pub fn new() -> Self {
        Self { timeout: None }
    }

    /// Commands that are known to hang (service control) get an explicit deadline.
    pub fn with_timeout(timeout: Duration) -> Self {
        Self {
            timeout: Some(timeout),
        }
    }
}

#[async_trait]
impl CommandExecutor for SystemExecutor {
    async fn run(&self, program: &str, args: &[&str]) -> PlatformResult<CommandOutput> {
        let mut command = Command::new(program);
        command
            .args(args)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(windows)]
        {
            const CREATE_NO_WINDOW: u32 = 0x0800_0000;
            command.creation_flags(CREATE_NO_WINDOW);
        }
        let future = async {
            let output = command.output().await?;
            let mut bytes = output.stdout;
            bytes.extend_from_slice(&output.stderr);
            Ok::<_, std::io::Error>(CommandOutput {
                stdout: bytes,
                status: output.status.code(),
                success: output.status.success(),
            })
        };
        match self.timeout {
            Some(timeout) => match tokio::time::timeout(timeout, future).await {
                Ok(result) => result.map_err(PlatformError::from),
                Err(_) => Err(PlatformError::message(format!("{program} 执行超时"))),
            },
            None => future.await.map_err(PlatformError::from),
        }
    }
}
