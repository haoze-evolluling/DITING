//! Small filesystem helpers shared by the Linux backends.
//!
//! Mirrors `desktop/service/internal/platform/linux/files.go`: parent directories are created
//! with 0700, and file modes only apply on creation so an existing file keeps its permissions.

use std::fs::{self, OpenOptions};
use std::io;
use std::path::Path;

#[cfg(unix)]
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};

/// Ensures the parent directory exists (0700), like Go's `ensureParentDir`.
pub(crate) fn ensure_parent_dir(path: &Path) -> io::Result<()> {
    let Some(parent) = path.parent() else {
        return Ok(());
    };
    if parent.as_os_str().is_empty() {
        return Ok(());
    }
    let mut builder = fs::DirBuilder::new();
    builder.recursive(true);
    #[cfg(unix)]
    builder.mode(0o700);
    builder.create(parent)
}

/// Writes a file after ensuring its parent exists. `mode` is applied only when creating.
pub(crate) fn write_file_mode(path: &Path, data: &[u8], mode: u32) -> io::Result<()> {
    ensure_parent_dir(path)?;
    let mut options = OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    options.mode(mode);
    let mut file = options.open(path)?;
    use std::io::Write;
    file.write_all(data)
}

/// Reads the complete contents of `path`.
pub(crate) fn read_file_at(path: &Path) -> io::Result<Vec<u8>> {
    fs::read(path)
}

/// True when `path` exists and is a regular file.
pub(crate) fn file_exists(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| !metadata.is_dir())
        .unwrap_or(false)
}

/// Deletes `path`, surfacing the filesystem error.
pub(crate) fn remove_path(path: &Path) -> io::Result<()> {
    fs::remove_file(path)
}

/// True when the error means "the path does not exist".
pub(crate) fn is_not_exist(error: &io::Error) -> bool {
    error.kind() == io::ErrorKind::NotFound
}

/// Deletes a file and treats a missing file as success, like Go's `removeFile`.
pub(crate) fn remove_file_if_exists(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if is_not_exist(&error) => Ok(()),
        Err(error) => Err(error),
    }
}
