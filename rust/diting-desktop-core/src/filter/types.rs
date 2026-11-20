use std::net::IpAddr;

pub use diting_desktop_api::config::ClientGroup;

pub const DEFAULT_CLIENT_GROUP_ID: &str = "default";

pub const REWRITE_TTL: u32 = 60;

pub const MAX_PAUSE_DURATION_SEC: i64 = 365 * 24 * 3600;

pub const REASON_IMPORTANT_ALLOW: &str = "important_allow";
pub const REASON_IMPORTANT_BLOCK: &str = "important_block";
pub const REASON_WHITELIST: &str = "whitelist";
pub const REASON_BLACKLIST: &str = "blacklist";
pub const REASON_WILDCARD_BLOCK: &str = "wildcard_block";
pub const REASON_REGEX_BLOCK: &str = "regex_block";

pub const REASON_SCHEDULE_INACTIVE: &str = "SCHEDULE_INACTIVE";
pub const REASON_SERVICE_SCHEDULE_INACTIVE: &str = "SERVICE_SCHEDULE_INACTIVE";
pub const REASON_ALLOWLIST_ONLY: &str = "ALLOWLIST_ONLY";
pub const REASON_DNSREWRITE: &str = "DNSREWRITE";
pub const REASON_RESPONSE_BLOCKED: &str = "RESPONSE_CNAME_BLOCKED";
pub const REASON_BOGUS_NXDOMAIN: &str = "BOGUS_NXDOMAIN";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum VerdictAction {
    #[default]
    Pass,
    Allow,
    Block,
    Rewrite,
}

impl VerdictAction {
    pub fn as_str(self) -> &'static str {
        match self {
            VerdictAction::Pass => "pass",
            VerdictAction::Allow => "allow",
            VerdictAction::Block => "block",
            VerdictAction::Rewrite => "rewrite",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RewriteRecord {
    pub kind: String,
    pub value: String,
    pub ttl: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RewriteResult {
    pub rcode: u8,
    pub records: Vec<RewriteRecord>,
    pub summary: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CheckHostResult {
    pub blocked: bool,
    pub action: VerdictAction,
    pub matched_rule: String,
    pub list_name: String,
    pub reason: String,
    pub rewritten: Option<RewriteResult>,
}

impl CheckHostResult {
    pub fn pass() -> Self {
        Self::default()
    }

    pub fn pass_with_reason(reason: &str) -> Self {
        Self {
            reason: reason.to_string(),
            ..Self::default()
        }
    }

    pub fn is_rewrite(&self) -> bool {
        self.action == VerdictAction::Rewrite && self.rewritten.is_some()
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct FilterStats {
    pub enabled: bool,
    pub total_rules: u32,
    pub active_lists: i32,
    pub total_queries: u64,
    pub blocked_queries: u64,
    pub allowed_queries: u64,
    pub block_rate: f64,
    pub schedule_active: bool,
    pub paused: bool,
    pub paused_remaining_sec: i64,
    pub paused_until_ms: i64,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PauseState {
    pub paused: bool,
    pub remaining_sec: i64,
    pub until_ms: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScheduleView {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockResponseConfig {
    pub block_mode: String,
    pub blocking_ipv4: String,
    pub blocking_ipv6: String,
}

#[derive(Debug, Clone, Default)]
pub struct GroupConfig {
    pub enabled: bool,
    pub groups: Vec<ClientGroup>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResponseRecordKind {
    A,
    Aaaa,
    Cname,
    Https,
    Svcb,
    Other,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResponseRecord {
    pub owner: String,
    pub kind: ResponseRecordKind,
    pub target: Option<String>,
}

impl ResponseRecord {
    pub fn address(owner: impl Into<String>, kind: ResponseRecordKind) -> Self {
        Self {
            owner: owner.into(),
            kind,
            target: None,
        }
    }

    pub fn cname(owner: impl Into<String>, target: impl Into<String>) -> Self {
        Self {
            owner: owner.into(),
            kind: ResponseRecordKind::Cname,
            target: Some(target.into()),
        }
    }

    pub fn svcb(owner: impl Into<String>, target: impl Into<String>) -> Self {
        Self {
            owner: owner.into(),
            kind: ResponseRecordKind::Svcb,
            target: Some(target.into()),
        }
    }

    pub fn other(owner: impl Into<String>) -> Self {
        Self {
            owner: owner.into(),
            kind: ResponseRecordKind::Other,
            target: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BogusNxDomainHit {
    pub ip: IpAddr,
    pub reason: String,
}

#[derive(Debug, thiserror::Error)]
pub enum FilterError {
    #[error("订阅列表 ID 已存在: {0}")]
    DuplicateList(String),
    #[error("找不到订阅列表: {0}")]
    ListNotFound(String),
    #[error("订阅列表 {0} 的 URL 不能为空")]
    EmptyUrl(String),
    #[error("获取规则源失败 ({url}): {message}")]
    Fetch {
        url: String,
        message: String,
        transient: bool,
    },
    #[error("保存规则缓存文件失败: {0}")]
    Io(String),
    #[error("规则索引任务失败: {0}")]
    Join(String),
}
