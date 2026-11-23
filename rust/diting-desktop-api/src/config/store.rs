use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use super::paths;
use super::Config;

pub trait ConfigStore: Send + Sync {
    fn load(&self) -> io::Result<Config>;
    fn save(&self, config: &Config) -> io::Result<()>;
    fn location(&self) -> PathBuf;
}

#[derive(Debug, Clone)]
pub struct FileConfigStore {
    path: PathBuf,
}

impl FileConfigStore {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub fn path(&self) -> &Path {
        &self.path
    }
}

impl ConfigStore for FileConfigStore {
    fn load(&self) -> io::Result<Config> {
        load_config(&self.path)
    }

    fn save(&self, config: &Config) -> io::Result<()> {
        save_config(&self.path, config)
    }

    fn location(&self) -> PathBuf {
        normalize_path(&self.path)
    }
}

pub fn default_config_path() -> PathBuf {
    paths::default_config_path()
}

pub fn load_config(path: &Path) -> io::Result<Config> {
    let path = normalize_path(path);
    let bytes = match fs::read(&path) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == io::ErrorKind::NotFound => return Ok(Config::default()),
        Err(error) => {
            return Err(io::Error::new(
                error.kind(),
                format!("failed to read config file ({}): {error}", path.display()),
            ));
        }
    };

    let mut config: Config = serde_json::from_slice(&bytes).map_err(|error| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("failed to parse config file ({}): {error}", path.display()),
        )
    })?;
    config.normalize();
    Ok(config)
}

pub fn save_config(path: &Path, config: &Config) -> io::Result<()> {
    let path = normalize_path(path);

    if let Some(dir) = path.parent() {
        if !dir.as_os_str().is_empty() {
            fs::create_dir_all(dir).map_err(|error| {
                io::Error::new(
                    error.kind(),
                    format!(
                        "failed to create config directory ({}): {error}",
                        dir.display()
                    ),
                )
            })?;
        }
    }

    let bytes = serde_json::to_vec_pretty(config).map_err(|error| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("failed to serialize config: {error}"),
        )
    })?;

    let mut temporary = path.clone().into_os_string();
    temporary.push(".tmp");
    let temporary = PathBuf::from(temporary);

    fs::write(&temporary, &bytes).map_err(|error| {
        io::Error::new(
            error.kind(),
            format!(
                "failed to write temporary config ({}): {error}",
                temporary.display()
            ),
        )
    })?;
    set_file_mode(&temporary);

    match fs::remove_file(&path) {
        Ok(()) => {}
        Err(error) if error.kind() == io::ErrorKind::NotFound => {}
        Err(error) => {
            let _ = fs::remove_file(&temporary);
            return Err(io::Error::new(
                error.kind(),
                format!(
                    "failed to replace config file ({}): {error}",
                    path.display()
                ),
            ));
        }
    }

    if let Err(error) = fs::rename(&temporary, &path) {
        let _ = fs::remove_file(&temporary);
        return Err(io::Error::new(
            error.kind(),
            format!(
                "failed to replace config file ({}): {error}",
                path.display()
            ),
        ));
    }

    Ok(())
}

fn normalize_path(path: &Path) -> PathBuf {
    if path.as_os_str().is_empty() {
        default_config_path()
    } else {
        path.to_path_buf()
    }
}

#[cfg(unix)]
fn set_file_mode(path: &Path) {
    use std::os::unix::fs::PermissionsExt;
    let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o644));
}

#[cfg(not(unix))]
fn set_file_mode(_path: &Path) {}
