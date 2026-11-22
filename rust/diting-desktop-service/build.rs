use std::path::{Path, PathBuf};

fn main() {
    // Windows resources are only needed for the Windows binary. The Linux
    // service packaged in the .deb must not require a Windows resource compiler.
    if std::env::var("CARGO_CFG_TARGET_OS").as_deref() != Ok("windows") {
        return;
    }

    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
    let root = match manifest.parent().and_then(Path::parent) {
        Some(root) => root.to_path_buf(),
        None => return,
    };
    let icon = root
        .join("desktop")
        .join("service")
        .join("build")
        .join("windows")
        .join("icon.ico");
    println!("cargo:rerun-if-changed={}", icon.display());
    if !icon.is_file() {
        println!("cargo:warning=未找到服务图标: {}", icon.display());
        return;
    }

    let version = read_version(&root.join("desktop").join("service").join("VERSION"))
        .unwrap_or_else(|| "0.0.0".to_string());

    // Resource strings stay ASCII so the generated .rc file is independent of
    // the machine's ANSI code page; the icon is the visible product identity.
    let mut resource = winresource::WindowsResource::new();
    resource.set_icon(icon.to_str().expect("icon path is valid UTF-8"));
    resource.set("CompanyName", "Diting");
    resource.set("FileDescription", "DITING DNS Service");
    resource.set("FileVersion", &format!("{version}.0"));
    resource.set("InternalName", "diting-service");
    resource.set("LegalCopyright", "Copyright 2026 DITING");
    resource.set("OriginalFilename", "diting-service.exe");
    resource.set("ProductName", "DITING DNS");
    resource.set("ProductVersion", &format!("{version}.0"));
    if let Err(error) = resource.compile() {
        panic!("编译 Windows 服务资源失败（图标/版本信息）: {error}");
    }
}

fn read_version(path: &Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let value = trimmed.strip_prefix("version:").unwrap_or(trimmed).trim();
        let value = value.split('+').next().unwrap_or("").trim();
        if !value.is_empty() {
            return Some(value.to_string());
        }
    }
    None
}
