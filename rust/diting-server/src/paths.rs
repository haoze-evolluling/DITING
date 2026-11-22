use std::path::{Path, PathBuf};

#[derive(Debug, Clone)]
pub struct ServerPaths {
    pub data_dir: PathBuf,
    pub config_path: PathBuf,
    pub socket_path: PathBuf,
    pub log_path: PathBuf,
    pub rules_dir: PathBuf,
    pub querylog_dir: PathBuf,
}

impl ServerPaths {
    pub fn new(data_dir: impl Into<PathBuf>) -> Self {
        let data_dir = data_dir.into();
        Self {
            config_path: data_dir.join("config.json"),
            socket_path: data_dir.join("control.sock"),
            log_path: data_dir.join("server.log"),
            rules_dir: data_dir.join("rules"),
            querylog_dir: data_dir.join("querylog"),
            data_dir,
        }
    }

    pub fn with_overrides(
        mut self,
        config_path: Option<&Path>,
        socket_path: Option<&Path>,
    ) -> Self {
        if let Some(path) = config_path {
            self.config_path = path.to_path_buf();
        }
        if let Some(path) = socket_path {
            self.socket_path = path.to_path_buf();
        }
        self
    }

    pub fn ensure_dirs(&self) -> std::io::Result<()> {
        std::fs::create_dir_all(&self.data_dir)?;
        std::fs::create_dir_all(&self.rules_dir)?;
        std::fs::create_dir_all(&self.querylog_dir)?;
        Ok(())
    }
}
