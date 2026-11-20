use std::path::PathBuf;
use std::process::Command;

fn main() {
    let manifest = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap_or_default());
    let pubspec = manifest
        .parent()
        .and_then(|path| path.parent())
        .map(|root| root.join("desktop").join("app").join("pubspec.yaml"));
    let version = pubspec
        .as_deref()
        .and_then(read_version)
        .unwrap_or_else(|| "dev".to_string());
    let build_time = command("git", &["log", "-1", "--format=%cI"])
        .or_else(|| Some(now_iso()))
        .unwrap_or_else(|| "dev".to_string());
    let commit =
        command("git", &["rev-parse", "--short", "HEAD"]).unwrap_or_else(|| "dev".to_string());

    println!("cargo:rustc-env=DITING_VERSION={version}");
    println!("cargo:rustc-env=DITING_BUILD_TIME={build_time}");
    println!("cargo:rustc-env=DITING_GIT_COMMIT={commit}");
    if let Some(path) = pubspec {
        println!("cargo:rerun-if-changed={}", path.display());
    }
}

fn read_version(path: &std::path::Path) -> Option<String> {
    let text = std::fs::read_to_string(path).ok()?;
    for line in text.lines() {
        let trimmed = line.trim();
        if let Some(value) = trimmed.strip_prefix("version:") {
            return Some(value.trim().split('+').next().unwrap_or("dev").to_string());
        }
    }
    None
}

fn command(program: &str, args: &[&str]) -> Option<String> {
    let output = Command::new(program).args(args).output().ok()?;
    if !output.status.success() {
        return None;
    }
    let text = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if text.is_empty() {
        None
    } else {
        Some(text)
    }
}

fn now_iso() -> String {
    match std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH) {
        Ok(duration) => format!("unix:{}", duration.as_secs()),
        Err(_) => "dev".to_string(),
    }
}
