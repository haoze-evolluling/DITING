//! Command-line surface, matching the former Go service's `cmd/service/cli.go`.
//!
//! The service manager launches the binary with `-run`; interactive invocations without arguments
//! print the version, which is also what a user double-clicking the executable expects.

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    Version,
    Run,
    Service(ServiceAction),
    PortCheck,
    Restore,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ServiceAction {
    Install,
    Uninstall,
    Start,
    Stop,
    Restart,
}

impl ServiceAction {
    pub fn parse(text: &str) -> Option<Self> {
        match text {
            "install" => Some(Self::Install),
            "uninstall" => Some(Self::Uninstall),
            "start" => Some(Self::Start),
            "stop" => Some(Self::Stop),
            "restart" => Some(Self::Restart),
            _ => None,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Install => "install",
            Self::Uninstall => "uninstall",
            Self::Start => "start",
            Self::Stop => "stop",
            Self::Restart => "restart",
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct Cli {
    pub command: Command,
    pub config_path: String,
    pub dns_port: u16,
    pub ipc_addr: String,
    pub token: String,
}

impl Command {
    fn default_command() -> Self {
        Self::Version
    }
}

impl Default for Command {
    fn default() -> Self {
        Self::default_command()
    }
}

/// Parses the legacy single-dash flags (`-run`, `-port 53`) and their double-dash spellings.
pub fn parse<I, S>(args: I) -> Result<Cli, String>
where
    I: IntoIterator<Item = S>,
    S: Into<String>,
{
    let mut args = args.into_iter().map(Into::into).peekable();
    // Drop the program name when present.
    if args.peek().is_some() {
        args.next();
    }
    let mut cli = Cli::default();
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "-v" | "--v" | "-version" | "--version" => cli.command = Command::Version,
            "-run" | "--run" => cli.command = Command::Run,
            "-check-ports" | "--check-ports" => cli.command = Command::PortCheck,
            "-restore" | "--restore" => cli.command = Command::Restore,
            "-service" | "--service" => {
                let value = args
                    .next()
                    .ok_or_else(|| "缺少 -service 的取值".to_string())?;
                let action = ServiceAction::parse(&value)
                    .ok_or_else(|| format!("不支持的服务操作: {value}"))?;
                cli.command = Command::Service(action);
            }
            "-config" | "--config" => {
                cli.config_path = args
                    .next()
                    .ok_or_else(|| "缺少 -config 的取值".to_string())?;
            }
            "-port" | "--port" => {
                let value = args.next().ok_or_else(|| "缺少 -port 的取值".to_string())?;
                cli.dns_port = value
                    .parse::<u16>()
                    .map_err(|_| format!("无效的 -port 取值: {value}"))?;
            }
            "-ipc-addr" | "--ipc-addr" => {
                cli.ipc_addr = args
                    .next()
                    .ok_or_else(|| "缺少 -ipc-addr 的取值".to_string())?;
            }
            "-token" | "--token" => {
                cli.token = args
                    .next()
                    .ok_or_else(|| "缺少 -token 的取值".to_string())?;
            }
            other => return Err(format!("未知参数: {other}")),
        }
    }
    Ok(cli)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_run_with_overrides() {
        let cli = parse([
            "diting-service",
            "-run",
            "-port",
            "5353",
            "-ipc-addr",
            "127.0.0.1:15354",
            "-config",
            "C:/tmp/config.json",
            "-token",
            "secret",
        ])
        .unwrap();
        assert_eq!(cli.command, Command::Run);
        assert_eq!(cli.dns_port, 5353);
        assert_eq!(cli.ipc_addr, "127.0.0.1:15354");
        assert_eq!(cli.config_path, "C:/tmp/config.json");
        assert_eq!(cli.token, "secret");
    }

    #[test]
    fn service_actions_and_errors() {
        assert_eq!(
            parse(["svc", "-service", "install"]).unwrap().command,
            Command::Service(ServiceAction::Install)
        );
        assert!(parse(["svc", "-service", "bogus"]).is_err());
        assert!(parse(["svc", "-port", "not-a-number"]).is_err());
        assert!(parse(["svc", "--unknown"]).is_err());
    }

    #[test]
    fn no_arguments_prints_version() {
        assert_eq!(parse(["svc"]).unwrap().command, Command::Version);
    }
}
