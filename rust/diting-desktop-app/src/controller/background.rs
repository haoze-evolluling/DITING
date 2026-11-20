use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

use serde::{Deserialize, Serialize};

use diting_desktop_api::config::LoginBgConfig;

use crate::controller::ControllerError;
use crate::AppRuntime;

const VALID_EXTENSIONS: [&str; 4] = [".webp", ".png", ".jpg", ".jpeg"];
const MAX_IMAGE_BYTES: usize = 10 * 1024 * 1024;
const MAX_URL_LEN: usize = 2048;

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LoginBackgroundResponse {
    #[serde(rename = "type")]
    pub kind: String,
    pub url: String,
    pub opacity: i32,
    pub blur: i32,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Default)]
pub struct SetLoginBackgroundInput {
    pub kind: String,
    pub url: String,
    pub opacity: i32,
    pub blur: i32,
    pub image: Option<Vec<u8>>,
}

pub struct BackgroundImage {
    pub data: Vec<u8>,
    pub content_type: String,
    pub modified_millis: i64,
}

fn storage_dir(runtime: &AppRuntime) -> PathBuf {
    let path = runtime.config_path();
    path.parent()
        .filter(|parent| !parent.as_os_str().is_empty())
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."))
}

fn detect_image(data: &[u8]) -> Option<(&'static str, &'static str)> {
    if data.len() >= 8 && data.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Some((".png", "image/png"));
    }
    if data.len() >= 3 && data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF {
        return Some((".jpg", "image/jpeg"));
    }
    if data.len() >= 12 && &data[0..4] == b"RIFF" && &data[8..12] == b"WEBP" {
        return Some((".webp", "image/webp"));
    }
    let probe = &data[..data.len().min(4096)];
    let text = String::from_utf8_lossy(probe).to_ascii_lowercase();
    if text.contains("<svg") || (text.contains("<?xml") && text.contains("svg")) {
        return Some((".svg", "image/svg+xml"));
    }
    None
}

fn find_existing(dir: &Path) -> Option<PathBuf> {
    for ext in VALID_EXTENSIONS {
        let path = dir.join(format!("login_bg{ext}"));
        if let Ok(metadata) = std::fs::metadata(&path) {
            if metadata.is_file() && metadata.len() > 0 {
                return Some(path);
            }
        }
    }
    None
}

fn clean_existing(dir: &Path) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if !name.starts_with("login_bg") {
            continue;
        }
        let lower = name.to_ascii_lowercase();
        if VALID_EXTENSIONS.iter().any(|ext| lower.ends_with(ext)) || lower.ends_with(".tmp") {
            let _ = std::fs::remove_file(entry.path());
        }
    }
}

fn response(
    kind: &str,
    url: &str,
    opacity: i32,
    blur: i32,
    updated_at: i64,
) -> LoginBackgroundResponse {
    LoginBackgroundResponse {
        kind: kind.to_string(),
        url: url.to_string(),
        opacity,
        blur,
        updated_at,
    }
}

impl AppRuntime {
    pub fn login_background(&self) -> LoginBackgroundResponse {
        let background = self.config().web.background;
        let dir = storage_dir(self);
        match background.kind.as_str() {
            "custom" => {
                if find_existing(&dir).is_none() {
                    return response("none", "", 40, 0, background.updated_at);
                }
                let url = format!("/api/v1/auth/background/image?t={}", background.updated_at);
                response(
                    "custom",
                    &url,
                    background.opacity,
                    background.blur,
                    background.updated_at,
                )
            }
            "url" if !background.url.is_empty() => response(
                "url",
                &background.url,
                background.opacity,
                background.blur,
                background.updated_at,
            ),
            _ => response("none", "", 40, 0, background.updated_at),
        }
    }

    pub fn set_login_background(
        &self,
        input: SetLoginBackgroundInput,
    ) -> Result<LoginBackgroundResponse, ControllerError> {
        let opacity = input.opacity.clamp(0, 100);
        let blur = input.blur.clamp(0, 20);
        let dir = storage_dir(self);

        if let Some(image) = input.image {
            if image.is_empty() {
                return Err(ControllerError::new("图片数据内容为空"));
            }
            if image.len() > MAX_IMAGE_BYTES {
                return Err(ControllerError::new("图片数据体积过大 (超过 10MB 限额)"));
            }
            let (ext, _) = detect_image(&image).ok_or_else(|| {
                ControllerError::new("图片文件头校验失败，仅支持 WebP、PNG、JPEG 与 SVG 格式")
            })?;
            std::fs::create_dir_all(&dir)
                .map_err(|error| ControllerError::new(format!("创建背景存储目录失败: {error}")))?;
            let target = dir.join(format!("login_bg{ext}"));
            let temporary = dir.join("login_bg_upload.tmp");
            std::fs::write(&temporary, &image)
                .map_err(|error| ControllerError::new(format!("写入背景临时文件失败: {error}")))?;
            clean_existing(&dir);
            let _ = std::fs::remove_file(&target);
            std::fs::rename(&temporary, &target).map_err(|error| {
                ControllerError::new(format!("持久化背景图片文件失败: {error}"))
            })?;

            let updated_at = now_unix();
            self.update_config(|config| {
                config.web.background = LoginBgConfig {
                    kind: "custom".to_string(),
                    url: "/api/v1/auth/background/image".to_string(),
                    opacity,
                    blur,
                    updated_at,
                };
            })
            .map_err(ControllerError::new)?;
            return Ok(self.login_background());
        }

        let trimmed = input.url.trim().to_string();
        if input.kind == "custom" || trimmed.contains("/api/v1/auth/background/image") {
            if find_existing(&dir).is_none() {
                return Err(ControllerError::new(
                    "服务端尚未存储自定义背景图片，请先上传本地图片",
                ));
            }
            let updated_at = now_unix();
            self.update_config(|config| {
                config.web.background = LoginBgConfig {
                    kind: "custom".to_string(),
                    url: "/api/v1/auth/background/image".to_string(),
                    opacity,
                    blur,
                    updated_at,
                };
            })
            .map_err(ControllerError::new)?;
            return Ok(self.login_background());
        }

        if trimmed.starts_with("http://") || trimmed.starts_with("https://") {
            if trimmed.len() > MAX_URL_LEN {
                return Err(ControllerError::new("图片网络链接长度超过 2048 字符上限"));
            }
            clean_existing(&dir);
            let updated_at = now_unix();
            self.update_config(|config| {
                config.web.background = LoginBgConfig {
                    kind: "url".to_string(),
                    url: trimmed.clone(),
                    opacity,
                    blur,
                    updated_at,
                };
            })
            .map_err(ControllerError::new)?;
            return Ok(self.login_background());
        }

        self.reset_login_background()?;
        Ok(self.login_background())
    }

    pub fn reset_login_background(&self) -> Result<LoginBackgroundResponse, ControllerError> {
        clean_existing(&storage_dir(self));
        let updated_at = now_unix();
        self.update_config(|config| {
            config.web.background = LoginBgConfig {
                kind: "none".to_string(),
                url: String::new(),
                opacity: 40,
                blur: 0,
                updated_at,
            };
        })
        .map_err(ControllerError::new)?;
        Ok(self.login_background())
    }

    pub fn login_background_image(&self) -> Option<BackgroundImage> {
        let dir = storage_dir(self);
        let path = find_existing(&dir)?;
        let data = std::fs::read(&path).ok()?;
        let metadata = std::fs::metadata(&path).ok()?;
        let modified_millis = metadata
            .modified()
            .ok()
            .and_then(|time| time.duration_since(UNIX_EPOCH).ok())
            .map(|duration| duration.as_millis() as i64)
            .unwrap_or(0);
        let ext = path
            .extension()
            .map(|ext| format!(".{}", ext.to_string_lossy().to_ascii_lowercase()))
            .unwrap_or_default();
        let content_type = match ext.as_str() {
            ".png" => "image/png",
            ".jpg" | ".jpeg" => "image/jpeg",
            ".svg" => "image/svg+xml",
            _ => "image/webp",
        };
        Some(BackgroundImage {
            data,
            content_type: content_type.to_string(),
            modified_millis,
        })
    }
}

fn now_unix() -> i64 {
    std::time::SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs() as i64)
        .unwrap_or(0)
}
