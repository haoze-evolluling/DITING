//! 桌面端配置备份文档。
//!
//! 备份文档只包含可移植的业务配置：DNS、上游、缓存、规则、重写、局域网、
//! 加密 DNS、隐私与日志策略等。管理员凭据、IPC 令牌、证书路径与口令、
//! 接管状态文件路径、登录页背景图片都属于本机专属或敏感内容，导出时剔除，
//! 导入时沿用本机现有值，避免备份文件泄露凭据或让服务失去可访问性。

use serde_json::{Map, Value};

use super::Config;

pub const FORMAT: &str = "diting-desktop-backup";
pub const VERSION: i64 = 1;

/// 解析后的备份文档；具体配置字段的校验发生在 [`resolve`]。
#[derive(Debug, Clone)]
pub struct BackupDocument {
    pub exported_at: i64,
    pub app_version: String,
    pub data: Map<String, Value>,
}

impl BackupDocument {
    pub fn section_keys(&self) -> Vec<String> {
        self.data.keys().cloned().collect()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BackupError {
    Empty,
    NotJson,
    RootNotObject,
    NotBackup,
    NoVersion,
    UnsupportedVersion(i64),
    NoData,
    InvalidData(String),
}

impl BackupError {
    pub fn message(&self) -> String {
        match self {
            BackupError::Empty => "备份文件内容为空".to_string(),
            BackupError::NotJson => "备份文件不是有效的 JSON".to_string(),
            BackupError::RootNotObject => "备份文件的根节点必须是 JSON 对象".to_string(),
            BackupError::NotBackup => "不是谛听桌面端配置备份文件".to_string(),
            BackupError::NoVersion => "备份文件缺少版本号".to_string(),
            BackupError::UnsupportedVersion(version) => {
                format!("备份文件版本 {version} 高于当前服务支持的版本 {VERSION}")
            }
            BackupError::NoData => "备份文件缺少配置数据".to_string(),
            BackupError::InvalidData(detail) => format!("备份配置解析失败: {detail}"),
        }
    }
}

/// 生成 JSON 备份文本，剔除敏感与本机专属字段。
pub fn export_document(config: &Config, exported_at_ms: i64) -> Result<String, serde_json::Error> {
    let mut data = serde_json::to_value(config)?;
    redact(&mut data);
    let document = serde_json::json!({
        "format": FORMAT,
        "version": VERSION,
        "exportedAt": exported_at_ms,
        "appVersion": crate::version::VERSION,
        "data": data,
    });
    let mut text = serde_json::to_string_pretty(&document)?;
    text.push('\n');
    Ok(text)
}

/// 校验外层结构并返回备份文档；不校验具体配置字段。
pub fn parse(text: &str) -> Result<BackupDocument, BackupError> {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return Err(BackupError::Empty);
    }
    let parsed: Value = serde_json::from_str(trimmed).map_err(|_| BackupError::NotJson)?;
    let record = parsed.as_object().ok_or(BackupError::RootNotObject)?;
    if record.get("format").and_then(Value::as_str) != Some(FORMAT) {
        return Err(BackupError::NotBackup);
    }
    let version = match record.get("version") {
        None => return Err(BackupError::NoVersion),
        Some(Value::Number(number)) => number.as_i64().unwrap_or(VERSION),
        Some(_) => return Err(BackupError::NotBackup),
    };
    if version > VERSION {
        return Err(BackupError::UnsupportedVersion(version));
    }
    if version < 1 {
        return Err(BackupError::NotBackup);
    }
    let data = record
        .get("data")
        .and_then(Value::as_object)
        .cloned()
        .ok_or(BackupError::NoData)?;
    let exported_at = record
        .get("exportedAt")
        .and_then(Value::as_i64)
        .unwrap_or(0);
    let app_version = record
        .get("appVersion")
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();
    Ok(BackupDocument {
        exported_at,
        app_version,
        data,
    })
}

/// 把备份数据合并到本机配置：业务字段采用备份值，本机专属字段保持现状。
pub fn resolve(document: &BackupDocument, current: &Config) -> Result<Config, BackupError> {
    let raw = Value::Object(document.data.clone());
    let mut next: Config =
        serde_json::from_value(raw).map_err(|error| BackupError::InvalidData(error.to_string()))?;
    next.ipc = current.ipc.clone();
    next.web = current.web.clone();
    next.encrypted.cert = current.encrypted.cert.clone();
    next.takeover.state_file_path = current.takeover.state_file_path.clone();
    // 规则与缓存文件均落在本机目录，迁移到其他设备时沿用目标机器的路径。
    next.filter.data_dir = current.filter.data_dir.clone();
    next.cache.persist_path = current.cache.persist_path.clone();
    next.normalize();
    Ok(next)
}

fn redact(value: &mut Value) {
    let Some(root) = value.as_object_mut() else {
        return;
    };
    // 管理服务地址、管理员凭据与登录背景图片都属于本机专属，不进入备份。
    root.remove("ipc");
    root.remove("web");
    if let Some(takeover) = root.get_mut("takeover").and_then(Value::as_object_mut) {
        takeover.remove("stateFilePath");
    }
    if let Some(encrypted) = root.get_mut("encrypted").and_then(Value::as_object_mut) {
        // 证书文件路径、PKCS#12 口令与私钥都存在本机，迁移时需重新导入证书。
        encrypted.remove("cert");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample() -> Config {
        let mut config = Config::default();
        config.cache.max_ttl_seconds = 1234;
        config.filter.custom_rules = vec!["||ads.example^".to_string()];
        config.dns.enable_ede = false;
        config.ipc.auth_token = "ipc-token-secret".to_string();
        config.web.username = "operator".to_string();
        config.web.password_hash = "password-hash-secret".to_string();
        config.web.salt = "salt-secret".to_string();
        config.encrypted.cert.pkcs12_password = "pkcs12-secret".to_string();
        config.encrypted.cert.key_file = "/root/private/cert.key".to_string();
        config.takeover.state_file_path = "/tmp/machine-state.json".to_string();
        config
    }

    #[test]
    fn export_keeps_business_config_and_drops_secrets() {
        let text = export_document(&sample(), 1_700_000_000_000).unwrap();
        assert!(text.contains("\"format\": \"diting-desktop-backup\""));
        assert!(text.contains("\"maxTtlSeconds\": 1234"));
        assert!(text.contains("ads.example"));
        assert!(!text.contains("ipc-token-secret"));
        assert!(!text.contains("password-hash-secret"));
        assert!(!text.contains("salt-secret"));
        assert!(!text.contains("pkcs12-secret"));
        assert!(!text.contains("/root/private/cert.key"));
        assert!(!text.contains("/tmp/machine-state.json"));
        assert!(!text.contains("\"ipc\""));
        assert!(!text.contains("\"web\""));
    }

    #[test]
    fn resolve_restores_business_fields_and_keeps_local_secrets() {
        let text = export_document(&sample(), 7).unwrap();
        let document = parse(&text).unwrap();
        assert_eq!(document.exported_at, 7);

        let mut local = Config::default();
        local.ipc.auth_token = "local-token".to_string();
        local.web.username = "local-admin".to_string();
        local.web.password_hash = "local-hash".to_string();
        local.encrypted.cert.key_file = "/local/cert.key".to_string();
        local.takeover.state_file_path = "/local/state.json".to_string();
        local.filter.data_dir = "/local/filters".to_string();
        local.cache.persist_path = "/local/cache.json".to_string();

        let merged = resolve(&document, &local).unwrap();
        assert_eq!(merged.cache.max_ttl_seconds, 1234);
        assert_eq!(
            merged.filter.custom_rules,
            vec!["||ads.example^".to_string()]
        );
        assert!(!merged.dns.enable_ede);
        assert_eq!(merged.ipc.auth_token, "local-token");
        assert_eq!(merged.web.username, "local-admin");
        assert_eq!(merged.web.password_hash, "local-hash");
        assert_eq!(merged.encrypted.cert.key_file, "/local/cert.key");
        assert_eq!(merged.takeover.state_file_path, "/local/state.json");
        assert_eq!(merged.filter.data_dir, "/local/filters");
        assert_eq!(merged.cache.persist_path, "/local/cache.json");
    }

    #[test]
    fn rejects_malformed_documents() {
        assert_eq!(parse("  ").unwrap_err(), BackupError::Empty);
        assert_eq!(parse("nope").unwrap_err(), BackupError::NotJson);
        assert_eq!(parse("[]").unwrap_err(), BackupError::RootNotObject);
        assert_eq!(parse(r#"{"foo":1}"#).unwrap_err(), BackupError::NotBackup);
        assert_eq!(
            parse(r#"{"format":"diting-desktop-backup","data":{}}"#).unwrap_err(),
            BackupError::NoVersion
        );
        assert_eq!(
            parse(r#"{"format":"diting-desktop-backup","version":99,"data":{}}"#).unwrap_err(),
            BackupError::UnsupportedVersion(99)
        );
        assert_eq!(
            parse(r#"{"format":"diting-desktop-backup","version":1}"#).unwrap_err(),
            BackupError::NoData
        );
    }

    #[test]
    fn empty_data_is_a_valid_document() {
        let document =
            parse(r#"{"format":"diting-desktop-backup","version":1,"data":{}}"#).unwrap();
        let merged = resolve(&document, &Config::default()).unwrap();
        assert_eq!(merged, Config::default());
    }
}
