use std::fs::{self, OpenOptions};
use std::io;
use std::path::Path;

#[cfg(unix)]
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt};

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

pub(crate) fn read_file_at(path: &Path) -> io::Result<Vec<u8>> {
    fs::read(path)
}

pub(crate) fn file_exists(path: &Path) -> bool {
    fs::metadata(path)
        .map(|metadata| !metadata.is_dir())
        .unwrap_or(false)
}

pub(crate) fn remove_path(path: &Path) -> io::Result<()> {
    fs::remove_file(path)
}

pub(crate) fn is_not_exist(error: &io::Error) -> bool {
    error.kind() == io::ErrorKind::NotFound
}

pub(crate) fn remove_file_if_exists(path: &Path) -> io::Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if is_not_exist(&error) => Ok(()),
        Err(error) => Err(error),
    }
}
