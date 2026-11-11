//! The engine's error type.
//!
//! The Go engine returned `error` from two entry points only (`ApplyDNSConfig`, `StartStandalone`)
//! and a plain string from the rest, and Kotlin shows those strings verbatim (`RuntimeDnsConfig`
//! puts `message` in the tile, `DitingDnsServerService` shows `"DNS 服务启动失败：…"`). The error
//! texts are therefore part of the contract, so this type keeps them and implements `Display`
//! instead of wrapping a foreign error.

use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EngineError {
    /// `parse DNS config: …` — the payload did not decode.
    ConfigParse(String),
    /// The normalized config was rejected (`canonicalDNSMode`, provider validation).
    ConfigInvalid(String),
    /// `IPv4 UDP Server failed to bind 0.0.0.0:port: …`
    Bind(String),
    /// The engine is not running, or its server could not be started.
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

/// The result type every fallible engine entry point returns.
pub type EngineResult<T> = Result<T, EngineError>;
