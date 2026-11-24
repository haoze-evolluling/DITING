use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::Once;
use std::time::Duration;

use reqwest::header::{ETAG, IF_MODIFIED_SINCE, IF_NONE_MATCH, LAST_MODIFIED};
use sha2::{Digest, Sha256};

pub(crate) const MAX_LIST_BYTES: usize = 50 * 1024 * 1024;

const USER_AGENT: &str = "DITING-DNS-Engine/1.0";
const TIMEOUT: Duration = Duration::from_secs(15);

/// reqwest 以 `rustls-no-provider` 编译，未安装默认 provider 时
/// `Client::builder()` 会直接 panic。这里与 workspace 其余 rustls 用法保持一致，
/// 进程内只安装一次 ring provider。
fn ensure_crypto_provider() {
    static INSTALL: Once = Once::new();
    INSTALL.call_once(|| {
        let _ = rustls::crypto::ring::default_provider().install_default();
    });
}

fn bundled_fallback_certs() -> Vec<reqwest::Certificate> {
    if !rustls_native_certs::load_native_certs().certs.is_empty() {
        return Vec::new();
    }
    let mut certs = Vec::new();
    for pem in diting_engine::resolver::trust::BUNDLED_ROOTS {
        if let Ok(parsed) = reqwest::Certificate::from_pem_bundle(pem.as_bytes()) {
            certs.extend(parsed);
        }
    }
    certs
}

pub(crate) struct FetchOutcome {
    pub(crate) data: Option<Vec<u8>>,
    pub(crate) etag: String,
    pub(crate) last_modified: String,
    pub(crate) not_modified: bool,
}

#[derive(Debug)]
pub(crate) enum FetchError {
    HttpStatus { status: u16, url: String },
    Transport { url: String, message: String },
    TooLarge { url: String, size: usize },
}

impl FetchError {
    pub(crate) fn is_transient(&self) -> bool {
        !matches!(self, FetchError::HttpStatus { .. })
    }

    pub(crate) fn message(&self) -> String {
        match self {
            FetchError::HttpStatus { status, url } => {
                format!("HTTP 状态码异常: {status} ({url})")
            }
            FetchError::Transport { message, .. } => message.clone(),
            FetchError::TooLarge { size, .. } => format!("规则源内容过大: {size} bytes"),
        }
    }

    pub(crate) fn url(&self) -> &str {
        match self {
            FetchError::HttpStatus { url, .. }
            | FetchError::Transport { url, .. }
            | FetchError::TooLarge { url, .. } => url,
        }
    }
}

pub(crate) async fn fetch_conditional(
    url: &str,
    etag: &str,
    last_modified: &str,
) -> Result<FetchOutcome, FetchError> {
    if !url.starts_with("http://") && !url.starts_with("https://") {
        let data = tokio::fs::read(url)
            .await
            .map_err(|error| FetchError::Transport {
                url: url.to_string(),
                message: error.to_string(),
            })?;
        if data.len() > MAX_LIST_BYTES {
            return Err(FetchError::TooLarge {
                url: url.to_string(),
                size: data.len(),
            });
        }
        return Ok(FetchOutcome {
            data: Some(data),
            etag: String::new(),
            last_modified: String::new(),
            not_modified: false,
        });
    }

    ensure_crypto_provider();

    let mut builder = reqwest::Client::builder()
        .timeout(TIMEOUT)
        .gzip(true)
        .user_agent(USER_AGENT);
    for cert in bundled_fallback_certs() {
        builder = builder.add_root_certificate(cert);
    }
    let client = builder.build().map_err(|error| FetchError::Transport {
        url: url.to_string(),
        message: error.to_string(),
    })?;

    let mut request = client.get(url);
    if !etag.is_empty() {
        request = request.header(IF_NONE_MATCH, etag);
    }
    if !last_modified.is_empty() {
        request = request.header(IF_MODIFIED_SINCE, last_modified);
    }

    let response = request
        .send()
        .await
        .map_err(|error| FetchError::Transport {
            url: url.to_string(),
            message: error.to_string(),
        })?;
    let status = response.status().as_u16();

    if status == 304 {
        return Ok(FetchOutcome {
            data: None,
            etag: etag.to_string(),
            last_modified: last_modified.to_string(),
            not_modified: true,
        });
    }
    if status != 200 {
        return Err(FetchError::HttpStatus {
            status,
            url: url.to_string(),
        });
    }

    let new_etag = header_value(&response, ETAG);
    let new_last_modified = header_value(&response, LAST_MODIFIED);
    if let Some(length) = response.content_length() {
        if length as usize > MAX_LIST_BYTES {
            return Err(FetchError::TooLarge {
                url: url.to_string(),
                size: length as usize,
            });
        }
    }
    let data = response
        .bytes()
        .await
        .map_err(|error| FetchError::Transport {
            url: url.to_string(),
            message: error.to_string(),
        })?
        .to_vec();
    if data.len() > MAX_LIST_BYTES {
        return Err(FetchError::TooLarge {
            url: url.to_string(),
            size: data.len(),
        });
    }

    Ok(FetchOutcome {
        data: Some(data),
        etag: new_etag,
        last_modified: new_last_modified,
        not_modified: false,
    })
}

fn header_value(response: &reqwest::Response, name: reqwest::header::HeaderName) -> String {
    response
        .headers()
        .get(name)
        .and_then(|value| value.to_str().ok())
        .unwrap_or_default()
        .to_string()
}

pub(crate) fn cache_path(data_dir: &str, id: &str) -> PathBuf {
    Path::new(data_dir).join(format!("{id}.txt"))
}

pub(crate) fn read_cache(data_dir: &str, id: &str) -> Option<Vec<u8>> {
    std::fs::read(cache_path(data_dir, id)).ok()
}

pub(crate) fn remove_cache(data_dir: &str, id: &str) {
    let _ = std::fs::remove_file(cache_path(data_dir, id));
}

pub(crate) fn write_cache_atomic(data_dir: &str, id: &str, data: &[u8]) -> std::io::Result<()> {
    let dir = Path::new(data_dir);
    std::fs::create_dir_all(dir)?;
    let final_path = dir.join(format!("{id}.txt"));
    let unique = format!(
        "{id}.{}.{}.tmp",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|value| value.as_nanos())
            .unwrap_or(0)
    );
    let tmp_path = dir.join(unique);

    let result = (|| -> std::io::Result<()> {
        let mut file = std::fs::File::create_new(&tmp_path)?;
        file.write_all(data)?;
        file.sync_all()?;
        drop(file);
        std::fs::rename(&tmp_path, &final_path)
    })();

    if result.is_err() {
        let _ = std::fs::remove_file(&tmp_path);
    }
    result
}

pub fn list_checksum(data: &[u8]) -> String {
    use std::fmt::Write as _;
    let digest = Sha256::digest(data);
    let mut out = String::with_capacity(64);
    for byte in digest {
        let _ = write!(out, "{byte:02x}");
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reqwest_client_builds_after_installing_crypto_provider() {
        ensure_crypto_provider();
        assert!(reqwest::Client::builder().build().is_ok());
    }

    #[test]
    fn atomic_write_replaces_the_cache() {
        let dir = std::env::temp_dir().join(format!(
            "diting-fetch-test-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        let dir_text = dir.to_string_lossy().to_string();
        write_cache_atomic(&dir_text, "list-a", b"first").expect("write");
        assert_eq!(
            read_cache(&dir_text, "list-a").as_deref(),
            Some(&b"first"[..])
        );
        write_cache_atomic(&dir_text, "list-a", b"second").expect("write");
        assert_eq!(
            read_cache(&dir_text, "list-a").as_deref(),
            Some(&b"second"[..])
        );
        remove_cache(&dir_text, "list-a");
        assert!(read_cache(&dir_text, "list-a").is_none());
        let _ = std::fs::remove_dir_all(dir);
    }

    #[test]
    fn checksum_is_sha256_hex() {
        assert_eq!(
            list_checksum(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}
