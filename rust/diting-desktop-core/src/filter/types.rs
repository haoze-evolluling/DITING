//! Public result and policy types for the desktop rule/filter engine.
//!
//! These mirror the Go `CheckHostResult`, `FilterStats`, `RewriteResult` and the JSON shapes the
//! IPC layer serialises. The DNS stage consumes [`CheckHostResult`], [`RewriteResult`] and
//! [`BlockResponseConfig`] directly; no HTTP code lives here.

use std::net::IpAddr;

pub use diting_desktop_api::config::ClientGroup;

/// Group id used when a query is not matched to a configured client group.
pub const DEFAULT_CLIENT_GROUP_ID: &str = "default";

/// Default TTL of `$dnsrewrite` answers (`DefaultRewriteTTL` in Go).
pub const REWRITE_TTL: u32 = 60;

/// Maximum duration of one timed pause (`MaxPauseDuration`: 365 days).
pub const MAX_PAUSE_DURATION_SEC: i64 = 365 * 24 * 3600;

/// Reason codes the kernel reports for ordinary rule hits.
pub const REASON_IMPORTANT_ALLOW: &str = "important_allow";
pub const REASON_IMPORTANT_BLOCK: &str = "important_block";
pub const REASON_WHITELIST: &str = "whitelist";
pub const REASON_BLACKLIST: &str = "blacklist";
pub const REASON_WILDCARD_BLOCK: &str = "wildcard_block";
pub const REASON_REGEX_BLOCK: &str = "regex_block";

/// The whole engine was paused or the global blocking window is closed.
pub const REASON_SCHEDULE_INACTIVE: &str = "SCHEDULE_INACTIVE";
/// A built-in service rule was hit outside that service's weekly window.
pub const REASON_SERVICE_SCHEDULE_INACTIVE: &str = "SERVICE_SCHEDULE_INACTIVE";
/// Allowlist-only mode turned an unmatched query into a block.
pub const REASON_ALLOWLIST_ONLY: &str = "ALLOWLIST_ONLY";
/// A `$dnsrewrite` rule answered the query.
pub const REASON_DNSREWRITE: &str = "DNSREWRITE";
/// A response-side alias-chain recheck found a blocked target.
pub const REASON_RESPONSE_BLOCKED: &str = "RESPONSE_CNAME_BLOCKED";
/// The bogus-NXDOMAIN detector rewrote an upstream answer.
pub const REASON_BOGUS_NXDOMAIN: &str = "BOGUS_NXDOMAIN";

/// What the request-side filter decided.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum VerdictAction {
    /// No rule matched (or filtering was disabled).
    #[default]
    Pass,
    /// An allow/whitelist rule matched.
    Allow,
    /// A blocklist rule matched.
    Block,
    /// A `$dnsrewrite` rule answered the name.
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

/// One answer record produced by a `$dnsrewrite` rule, in the API rewrite-record shape.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RewriteRecord {
    /// Record type name (`A`, `AAAA`, `CNAME`, `TXT`, `MX`, `SRV`, `NS`, `PTR`, `HTTPS`, `SVCB`).
    pub kind: String,
    /// Record value as presented to the user (no trailing dot on domain targets).
    pub value: String,
    /// Per-record TTL (`REWRITE_TTL` unless a caller overrides it).
    pub ttl: u32,
}

/// The answer a `$dnsrewrite` rule declared for one query.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RewriteResult {
    /// Answer code; when this is not `0` the record list is empty.
    pub rcode: u8,
    /// Records to place in the answer section. Empty with `rcode == 0` is authoritative NODATA.
    pub records: Vec<RewriteRecord>,
    /// Human-readable form of each record, like Go's `dns.RR.String()`.
    pub summary: Vec<String>,
}

/// The result of a request-side filter evaluation.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct CheckHostResult {
    pub blocked: bool,
    pub action: VerdictAction,
    /// Raw text of the winning rule (empty when no rule matched).
    pub matched_rule: String,
    /// Source name: `custom`, a subscription list id, or `service:<id>`.
    pub list_name: String,
    /// Reason code; empty for a plain pass.
    pub reason: String,
    /// Present only when `action == Rewrite`.
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

    /// `CheckHostResult.IsRewrite`.
    pub fn is_rewrite(&self) -> bool {
        self.action == VerdictAction::Rewrite && self.rewritten.is_some()
    }
}

/// Runtime counters and schedule state (`FilterStats`).
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct FilterStats {
    pub enabled: bool,
    pub total_rules: u32,
    pub active_lists: i32,
    pub total_queries: u64,
    pub blocked_queries: u64,
    pub allowed_queries: u64,
    /// `blockedQueries / totalQueries * 100`.
    pub block_rate: f64,
    /// The global blocking window is open (or no window is configured).
    pub schedule_active: bool,
    pub paused: bool,
    pub paused_remaining_sec: i64,
    pub paused_until_ms: i64,
}

/// Current timed-pause state.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct PauseState {
    pub paused: bool,
    pub remaining_sec: i64,
    /// Unix milliseconds; `None` when not paused.
    pub until_ms: Option<i64>,
}

/// Display view of the schedule that is active right now.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ScheduleView {
    pub id: String,
    pub name: String,
}

/// Block-response policy after applying a group override.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BlockResponseConfig {
    pub block_mode: String,
    pub blocking_ipv4: String,
    pub blocking_ipv6: String,
}

/// Client-group configuration handed to the engine.
///
/// The groups themselves come from `diting-desktop-api`; the engine only adds the enabled switch.
#[derive(Debug, Clone, Default)]
pub struct GroupConfig {
    pub enabled: bool,
    pub groups: Vec<ClientGroup>,
}

/// The kind of an answer record, for response-side alias-chain extraction.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ResponseRecordKind {
    A,
    Aaaa,
    Cname,
    Https,
    Svcb,
    /// Any other record type; contributes no recheck name.
    Other,
}

/// One answer record the response recheck needs to see.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ResponseRecord {
    pub owner: String,
    pub kind: ResponseRecordKind,
    /// CNAME/SVCB/HTTPS target, when the record carries one.
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

/// A bogus-NXDOMAIN hit found in an upstream answer.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BogusNxDomainHit {
    pub ip: IpAddr,
    /// The block reason the DNS stage can attach to the rewritten NXDOMAIN.
    pub reason: String,
}

/// Errors raised by subscription management and background refreshes.
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
        /// Transport/timeout failures may fall back to the local cache; HTTP errors may not.
        transient: bool,
    },
    #[error("保存规则缓存文件失败: {0}")]
    Io(String),
    #[error("规则索引任务失败: {0}")]
    Join(String),
}
