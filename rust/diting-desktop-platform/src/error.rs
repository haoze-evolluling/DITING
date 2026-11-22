use diting_desktop_api::platform_types::PortCheckResult;

#[derive(Debug, thiserror::Error)]
pub enum PlatformError {
    #[error("{0}")]
    Message(String),
    #[error("{0}")]
    Io(#[from] std::io::Error),
    #[error("{0}")]
    Json(#[from] serde_json::Error),
    #[error("53 端口已被占用: {}", .0.diagnostic)]
    PortConflict(Box<PortCheckResult>),
}

impl PlatformError {
    pub fn message(text: impl Into<String>) -> Self {
        Self::Message(text.into())
    }

    pub fn port_conflict(result: PortCheckResult) -> Self {
        Self::PortConflict(Box::new(result))
    }

    pub fn port_result(&self) -> Option<&PortCheckResult> {
        match self {
            Self::PortConflict(result) => Some(result),
            _ => None,
        }
    }
}

impl From<String> for PlatformError {
    fn from(value: String) -> Self {
        Self::Message(value)
    }
}

impl From<&str> for PlatformError {
    fn from(value: &str) -> Self {
        Self::Message(value.to_string())
    }
}

pub type PlatformResult<T> = Result<T, PlatformError>;
