use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EngineError {
    ConfigParse(String),
    ConfigInvalid(String),
    Bind(String),
    State(String),
}

impl EngineError {
    pub fn config_parse(message: impl Into<String>) -> Self {
        Self::ConfigParse(message.into())
    }

    pub fn config_invalid(message: impl Into<String>) -> Self {
        Self::ConfigInvalid(message.into())
    }

    pub fn bind(message: impl Into<String>) -> Self {
        Self::Bind(message.into())
    }

    pub fn state(message: impl Into<String>) -> Self {
        Self::State(message.into())
    }
}

impl fmt::Display for EngineError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ConfigParse(message) => f.write_str(message),
            Self::ConfigInvalid(message) => f.write_str(message),
            Self::Bind(message) => f.write_str(message),
            Self::State(message) => f.write_str(message),
        }
    }
}

impl std::error::Error for EngineError {}

pub type EngineResult<T> = Result<T, EngineError>;
