pub fn is_blank(text: &str) -> bool {
    text.trim().is_empty()
}

pub fn lowercase(text: &str) -> String {
    text.to_lowercase()
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LogMode {
    All,
    BlockedAndErrors,
    Off,
}

impl LogMode {
    pub fn from_tag(tag: u8) -> Option<Self> {
        match tag {
            0 => Some(Self::All),
            1 => Some(Self::BlockedAndErrors),
            2 => Some(Self::Off),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct DnsInput {
    pub timestamp: i64,
    pub domain: String,
    pub query_type: i32,
    pub blocked: bool,
    pub blocked_by: String,
    pub error: String,
    pub cached: bool,
    pub app: String,
    pub resolved: String,
    pub elapsed_ms: i64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DnsResult {
    Error,
    Rewritten,
    Blocked,
    Passed,
}

impl DnsResult {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Error => "ERROR",
            Self::Rewritten => "REWRITTEN",
            Self::Blocked => "BLOCKED",
            Self::Passed => "PASSED",
        }
    }

    pub fn tag(self) -> u8 {
        match self {
            Self::Error => 0,
            Self::Rewritten => 1,
            Self::Blocked => 2,
            Self::Passed => 3,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DnsRow {
    pub timestamp: i64,
    pub query_name: String,
    pub query_type: i32,
    pub result: DnsResult,
    pub message: Option<String>,
    pub cached: bool,
    pub block_subscription_id: Option<i64>,
    pub package_name: Option<String>,
}

pub fn dns_result(input: &DnsInput) -> DnsResult {
    if !is_blank(&input.error) {
        DnsResult::Error
    } else if input.blocked_by.starts_with("rewrite=") {
        DnsResult::Rewritten
    } else if input.blocked {
        DnsResult::Blocked
    } else {
        DnsResult::Passed
    }
}

pub fn dns_row(input: &DnsInput, mode: LogMode, now_ms: i64) -> Option<DnsRow> {
    if is_blank(&input.domain) {
        return None;
    }
    let result = dns_result(input);
    if mode == LogMode::BlockedAndErrors && result == DnsResult::Passed {
        return None;
    }

    let mut parts: Vec<String> = Vec::new();
    if !is_blank(&input.app) {
        parts.push(format!("app={}", input.app));
    }
    if !is_blank(&input.resolved) {
        parts.push(format!("resolved={}", input.resolved));
    }
    if !is_blank(&input.blocked_by) {
        parts.push(format!("blocked_by={}", input.blocked_by));
    }
    if !is_blank(&input.error) {
        parts.push(format!("error={}", input.error));
    }
    if input.elapsed_ms > 0 {
        parts.push(format!("elapsed={}ms", input.elapsed_ms));
    }
    let message = if parts.is_empty() {
        None
    } else {
        Some(parts.join(", "))
    };

    Some(DnsRow {
        timestamp: if input.timestamp > 0 {
            input.timestamp
        } else {
            now_ms
        },
        query_name: lowercase(&input.domain),
        query_type: input.query_type,
        result,
        message,
        cached: input.cached,
        block_subscription_id: subscription_id(&input.blocked_by),
        package_name: if is_blank(&input.app) {
            None
        } else {
            Some(input.app.clone())
        },
    })
}

pub fn subscription_id(blocked_by: &str) -> Option<i64> {
    blocked_by.split(',').map(str::trim).find_map(|token| {
        parse_sub_id(token).or_else(|| {
            token
                .rsplit_once(':')
                .and_then(|(_, tail)| parse_sub_id(tail.trim()))
        })
    })
}

fn parse_sub_id(token: &str) -> Option<i64> {
    token
        .strip_prefix("sub_")
        .and_then(|rest| rest.parse::<i64>().ok())
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct HttpInput {
    pub package_name: String,
    pub authority: String,
    pub protocol: String,
    pub outcome: String,
    pub matched_rule: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct HttpRow {
    pub timestamp: i64,
    pub package_name: String,
    pub authority: Option<String>,
    pub protocol: String,
    pub outcome: String,
    pub matched_rule: Option<String>,
    pub block_subscription_id: Option<i64>,
}

pub fn http_row(input: &HttpInput, mode: LogMode, now_ms: i64) -> Option<HttpRow> {
    let outcome = normalized_outcome(&input.outcome);
    if mode == LogMode::Off {
        return None;
    }
    if mode == LogMode::BlockedAndErrors && is_pass_through(&input.outcome) {
        return None;
    }
    Some(HttpRow {
        timestamp: now_ms,
        package_name: if is_blank(&input.package_name) {
            "unknown".to_string()
        } else {
            input.package_name.clone()
        },
        authority: optional_text(&input.authority),
        protocol: input.protocol.clone(),
        outcome,
        matched_rule: optional_text(&input.matched_rule),
        block_subscription_id: subscription_id(&input.matched_rule),
    })
}

pub fn normalized_outcome(outcome: &str) -> String {
    if is_blank(outcome) {
        "error".to_string()
    } else {
        outcome.to_string()
    }
}

pub fn is_pass_through(outcome: &str) -> bool {
    matches!(outcome, "allowed" | "passthrough")
}

pub fn optional_text(value: &str) -> Option<String> {
    if is_blank(value) {
        None
    } else {
        Some(value.to_string())
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct RaceInput {
    pub query_name: String,
    pub query_type: i32,
    pub strategy: String,
    pub provider_count: i32,
    pub success: bool,
    pub elapsed_ms: i64,
    pub selected_provider_id: String,
    pub selected_elapsed_ms: i64,
    pub winner_provider_id: String,
    pub winner_elapsed_ms: i64,
    pub fallback_used: bool,
    pub fallback_success: bool,
    pub error_message: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct RaceRow {
    pub timestamp: i64,
    pub query_name: String,
    pub query_type: i32,
    pub strategy: String,
    pub provider_count: i32,
    pub success: bool,
    pub elapsed_ms: i64,
    pub selected_provider_id: Option<String>,
    pub selected_elapsed_ms: Option<i64>,
    pub winner_provider_id: Option<String>,
    pub winner_elapsed_ms: Option<i64>,
    pub fallback_used: bool,
    pub fallback_success: bool,
    pub message: Option<String>,
}

pub fn race_row(input: &RaceInput, now_ms: i64) -> Option<RaceRow> {
    if is_blank(&input.query_name) {
        return None;
    }
    Some(RaceRow {
        timestamp: now_ms,
        query_name: lowercase(&input.query_name),
        query_type: input.query_type,
        strategy: input.strategy.clone(),
        provider_count: input.provider_count,
        success: input.success,
        elapsed_ms: input.elapsed_ms,
        selected_provider_id: optional_text(&input.selected_provider_id),
        selected_elapsed_ms: (input.selected_elapsed_ms > 0).then_some(input.selected_elapsed_ms),
        winner_provider_id: optional_text(&input.winner_provider_id),
        winner_elapsed_ms: (input.winner_elapsed_ms > 0).then_some(input.winner_elapsed_ms),
        fallback_used: input.fallback_used,
        fallback_success: input.fallback_success,
        message: optional_text(&input.error_message),
    })
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct BootstrapInput {
    pub ip_id: String,
    pub ip_name: String,
    pub ip: String,
    pub host: String,
    pub success: bool,
    pub elapsed_ms: i64,
    pub fallback_used: bool,
    pub error_message: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BootstrapRow {
    pub timestamp: i64,
    pub ip_id: String,
    pub ip_name: String,
    pub ip: String,
    pub host: String,
    pub success: bool,
    pub elapsed_ms: i64,
    pub fallback_used: bool,
    pub message: Option<String>,
}

pub fn bootstrap_row(input: &BootstrapInput, now_ms: i64) -> Option<BootstrapRow> {
    if is_blank(&input.host) {
        return None;
    }
    Some(BootstrapRow {
        timestamp: now_ms,
        ip_id: if is_blank(&input.ip_id) {
            "unknown".to_string()
        } else {
            input.ip_id.clone()
        },
        ip_name: if is_blank(&input.ip_name) {
            input.ip_id.clone()
        } else {
            input.ip_name.clone()
        },
        ip: input.ip.clone(),
        host: lowercase(&input.host),
        success: input.success,
        elapsed_ms: input.elapsed_ms,
        fallback_used: input.fallback_used,
        message: optional_text(&input.error_message),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn dns(domain: &str) -> DnsInput {
        DnsInput {
            domain: domain.to_string(),
            ..DnsInput::default()
        }
    }

    #[test]
    fn dns_result_follows_the_error_rewrite_block_order() {
        let mut input = dns("example.com");
        assert_eq!(dns_result(&input), DnsResult::Passed);
        input.blocked = true;
        assert_eq!(dns_result(&input), DnsResult::Blocked);
        input.blocked_by = "rewrite=1.2.3.4".into();
        assert_eq!(dns_result(&input), DnsResult::Rewritten);
        input.error = "timeout".into();
        assert_eq!(dns_result(&input), DnsResult::Error);
        input.error = "  ".into();
        assert_eq!(dns_result(&input), DnsResult::Rewritten);
    }

    #[test]
    fn dns_row_builds_the_message_in_the_kotlin_order() {
        let input = DnsInput {
            timestamp: 1_700_000_000_123,
            domain: "Ads.Example.COM".into(),
            query_type: 1,
            blocked: true,
            blocked_by: "sub_42,firewall:3".into(),
            error: String::new(),
            cached: true,
            app: "com.example.app".into(),
            resolved: "1.2.3.4".into(),
            elapsed_ms: 12,
        };
        let row = dns_row(&input, LogMode::All, 5).unwrap();
        assert_eq!(row.timestamp, 1_700_000_000_123);
        assert_eq!(row.query_name, "ads.example.com");
        assert_eq!(row.result, DnsResult::Blocked);
        assert_eq!(
            row.message.as_deref(),
            Some(
                "app=com.example.app, resolved=1.2.3.4, blocked_by=sub_42,firewall:3, elapsed=12ms"
            )
        );
        assert_eq!(row.block_subscription_id, Some(42));
        assert_eq!(row.package_name.as_deref(), Some("com.example.app"));

        let bare = DnsInput {
            domain: "example.com".into(),
            ..DnsInput::default()
        };
        let row = dns_row(&bare, LogMode::All, 777).unwrap();
        assert_eq!(row.timestamp, 777);
        assert_eq!(row.message, None);
        assert_eq!(row.package_name, None);
    }

    #[test]
    fn dns_mode_filter_only_hides_passed_rows() {
        let passed = dns("example.com");
        assert!(dns_row(&passed, LogMode::BlockedAndErrors, 0).is_none());
        let mut blocked = passed.clone();
        blocked.blocked = true;
        assert!(dns_row(&blocked, LogMode::BlockedAndErrors, 0).is_some());
        assert!(dns_row(&blocked, LogMode::Off, 0).is_some());
        assert!(dns_row(&dns("   "), LogMode::All, 0).is_none());
    }

    #[test]
    fn subscription_ids_come_from_the_first_sub_token() {
        assert_eq!(subscription_id("sub_7"), Some(7));
        assert_eq!(subscription_id("firewall:1, sub_9 "), Some(9));
        assert_eq!(subscription_id("sub_"), None);
        assert_eq!(subscription_id("sub_abc,sub_3"), Some(3));
        assert_eq!(subscription_id(""), None);
        assert_eq!(subscription_id("sub_99999999999999999999"), None);
        assert_eq!(subscription_id("conn:host:sub_5"), Some(5));
        assert_eq!(subscription_id("conn:host:sub_5, sub_9"), Some(5));
        assert_eq!(subscription_id("conn:host:ads.example.com"), None);
        assert_eq!(subscription_id("firewall:uid_blocked"), None);
    }

    #[test]
    fn a_connection_layer_rule_block_keeps_its_subscription() {
        let input = DnsInput {
            domain: "ads.example.com".into(),
            query_type: 0,
            blocked: true,
            blocked_by: "conn:host:sub_5".into(),
            ..DnsInput::default()
        };
        let row = dns_row(&input, LogMode::All, 0).unwrap();
        assert_eq!(row.result, DnsResult::Blocked);
        assert_eq!(row.block_subscription_id, Some(5));
    }

    #[test]
    fn http_rows_default_blanks_and_honour_the_pass_through_filter() {
        let input = HttpInput {
            package_name: "  ".into(),
            authority: String::new(),
            protocol: String::new(),
            outcome: String::new(),
            matched_rule: "  ".into(),
        };
        let row = http_row(&input, LogMode::All, 9).unwrap();
        assert_eq!(row.package_name, "unknown");
        assert_eq!(row.authority, None);
        assert_eq!(row.outcome, "error");
        assert_eq!(row.matched_rule, None);
        assert_eq!(row.block_subscription_id, None);

        let blank_outcome = HttpInput::default();
        assert!(http_row(&blank_outcome, LogMode::BlockedAndErrors, 0).is_some());
        let allowed = HttpInput {
            outcome: "allowed".into(),
            ..HttpInput::default()
        };
        assert!(http_row(&allowed, LogMode::BlockedAndErrors, 0).is_none());
        assert!(http_row(&allowed, LogMode::All, 0).is_some());
        assert!(http_row(&allowed, LogMode::Off, 0).is_none());
        let cased = HttpInput {
            outcome: "Allowed".into(),
            ..HttpInput::default()
        };
        assert!(http_row(&cased, LogMode::BlockedAndErrors, 0).is_some());
    }

    #[test]
    fn http_domain_rule_blocks_are_attributed_to_their_subscription() {
        let blocked = HttpInput {
            package_name: "com.app".into(),
            authority: "ads.example.com".into(),
            protocol: "https".into(),
            outcome: "blocked".into(),
            matched_rule: "sub_12".into(),
        };
        let row = http_row(&blocked, LogMode::All, 0).unwrap();
        assert_eq!(row.outcome, "blocked");
        assert_eq!(row.block_subscription_id, Some(12));

        let by_request_rule = HttpInput {
            matched_rule: "||ads^".into(),
            ..blocked
        };
        assert_eq!(
            http_row(&by_request_rule, LogMode::All, 0)
                .unwrap()
                .block_subscription_id,
            None
        );
    }

    #[test]
    fn race_rows_keep_zero_elapsed_as_null() {
        let input = RaceInput {
            query_name: " Example.COM ".into(),
            query_type: 28,
            strategy: "smart_prediction".into(),
            provider_count: 3,
            success: true,
            elapsed_ms: 40,
            selected_provider_id: "p1".into(),
            selected_elapsed_ms: 0,
            winner_provider_id: String::new(),
            winner_elapsed_ms: 12,
            fallback_used: false,
            fallback_success: false,
            error_message: String::new(),
        };
        let row = race_row(&input, 100).unwrap();
        assert_eq!(row.query_name, " example.com ");
        assert_eq!(row.selected_elapsed_ms, None);
        assert_eq!(row.winner_elapsed_ms, Some(12));
        assert_eq!(row.winner_provider_id, None);
        assert_eq!(row.message, None);
        assert!(race_row(&RaceInput::default(), 0).is_none());
    }

    #[test]
    fn bootstrap_rows_fall_back_to_the_raw_id() {
        let input = BootstrapInput {
            ip_id: String::new(),
            ip_name: "Cloudflare".into(),
            ip: "1.1.1.1".into(),
            host: "DNS.Google".into(),
            success: true,
            elapsed_ms: 7,
            fallback_used: false,
            error_message: String::new(),
        };
        let row = bootstrap_row(&input, 0).unwrap();
        assert_eq!(row.ip_id, "unknown");
        assert_eq!(row.ip_name, "Cloudflare");
        assert_eq!(row.host, "dns.google");
        assert_eq!(row.message, None);

        let blank_id = BootstrapInput {
            ip_name: String::new(),
            ..input
        };
        let row = bootstrap_row(&blank_id, 0).unwrap();
        assert_eq!(row.ip_name, "");
        assert!(bootstrap_row(&BootstrapInput::default(), 0).is_none());
    }
}
