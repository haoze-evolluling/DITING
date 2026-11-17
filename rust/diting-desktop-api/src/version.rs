//! Build-time version information.
//!
//! The single source of truth is `desktop/app/pubspec.yaml`'s `version:` line; the service
//! crate's `build.rs` reads it and injects it through `DITING_VERSION`/`DITING_BUILD_TIME`/
//! `DITING_GIT_COMMIT`, so `-v` and `/api/v1/status` report the same values the Go build did.

pub const VERSION: &str = match option_env!("DITING_VERSION") {
    Some(value) => value,
    None => "dev",
};

pub const BUILD_TIME: &str = match option_env!("DITING_BUILD_TIME") {
    Some(value) => value,
    None => "dev",
};

pub const GIT_COMMIT: &str = match option_env!("DITING_GIT_COMMIT") {
    Some(value) => value,
    None => "dev",
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct VersionInfo {
    pub version: &'static str,
    pub build_time: &'static str,
    pub git_commit: &'static str,
}

pub const fn info() -> VersionInfo {
    VersionInfo {
        version: VERSION,
        build_time: BUILD_TIME,
        git_commit: GIT_COMMIT,
    }
}
