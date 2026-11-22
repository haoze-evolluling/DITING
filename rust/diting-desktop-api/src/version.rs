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
