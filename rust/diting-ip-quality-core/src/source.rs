//! One public IP-intelligence reply in, one source row out. The row keeps the legacy status tokens
//! (`命中`, `失败`, `超时`, `限流`) because the result page maps them directly, and every rule that
//! decides one lives here.

use serde_json::{json, Map, Value};

/// The three endpoints the checker queries, in report order.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Source {
    IpApi,
    IpWhoIs,
    IpInfo,
}

impl Source {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "ipApi" => Some(Self::IpApi),
            "ipWhoIs" => Some(Self::IpWhoIs),
            "ipInfo" => Some(Self::IpInfo),
            _ => None,
        }
    }
}

fn text_like(value: Option<&Value>) -> String {
    match value {
        None | Some(Value::Null) => String::new(),
        Some(Value::String(text)) => text.clone(),
        Some(Value::Bool(flag)) => flag.to_string(),
        Some(Value::Number(number)) => number.to_string(),
        Some(other) => other.to_string(),
    }
}

/// Dart's `a ?? b ?? ''`: a present empty string wins over the next key.
fn first_present(object: &Map<String, Value>, keys: &[&str]) -> String {
    for key in keys {
        if let Some(value) = object.get(*key) {
            if !value.is_null() {
                return text_like(Some(value));
            }
        }
    }
    String::new()
}

fn row(
    status: &str,
    ip_type: Option<&str>,
    organization: Option<&str>,
    asn: Option<&str>,
    detail: Option<&str>,
) -> Value {
    json!({
        "status": status,
        "ipType": ip_type,
        "organization": organization,
        "asn": asn,
        "detail": detail,
    })
}

fn failure(detail: Option<&str>) -> Value {
    row("失败", None, None, None, detail)
}

fn invalid_json() -> Value {
    failure(Some("响应不是合法 JSON"))
}

/// Infers the connection type from the ISP/organization text with the legacy keyword table. Mobile
/// is checked first, datacenter second; unknown stays business so a labelled datacenter is never
/// presented as a clean residential address.
fn classify(text: &str) -> &'static str {
    let lower = text.to_lowercase();
    const MOBILE: &[&str] = &[
        "mobile",
        "wireless",
        "cellular",
        "china mobile",
        "中国移动",
        "china unicom",
        "中国联通",
        "china telecom",
        "中国电信",
        "4g",
        "5g",
    ];
    const DATACENTER: &[&str] = &[
        "hosting",
        "datacenter",
        "data center",
        "cloud",
        "server",
        "vps",
        "amazon",
        "aws",
        "google",
        "microsoft",
        "azure",
        "digitalocean",
        "linode",
        "vultr",
        "ovh",
        "hetzner",
        "cloudflare",
        "alibaba",
        "tencent",
        "leaseweb",
        "contabo",
        "oracle",
    ];
    for keyword in MOBILE {
        if lower.contains(keyword) {
            return "移动";
        }
    }
    for keyword in DATACENTER {
        if lower.contains(keyword) {
            return "机房";
        }
    }
    if lower.contains("university") || lower.contains("college") {
        return "商业";
    }
    "商业"
}

/// First `AS<digits>` anywhere in the text.
fn asn_of(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut index = 0;
    while index + 1 < bytes.len() {
        if bytes[index] == b'A' && bytes[index + 1] == b'S' {
            let mut end = index + 2;
            while end < bytes.len() && bytes[end].is_ascii_digit() {
                end += 1;
            }
            if end > index + 2 {
                return text[index..end].to_owned();
            }
        }
        index += 1;
    }
    String::new()
}

/// `AS<digits>` plus its following whitespace at the very start, then trim.
fn org_name_of(text: &str) -> String {
    let bytes = text.as_bytes();
    let mut rest = text;
    if bytes.len() >= 3 && bytes[0] == b'A' && bytes[1] == b'S' {
        let mut end = 2;
        while end < bytes.len() && bytes[end].is_ascii_digit() {
            end += 1;
        }
        if end > 2 {
            rest = &text[end..];
        }
    }
    rest.trim().to_owned()
}

fn message_detail(object: &Map<String, Value>) -> String {
    text_like(object.get("message"))
}

fn ip_api(body: &str) -> Value {
    let decoded: Value = match serde_json::from_str(body) {
        Ok(value) => value,
        Err(_) => return invalid_json(),
    };
    let Some(object) = decoded.as_object() else {
        return failure(None);
    };
    if object.get("status").and_then(Value::as_str) != Some("success") {
        return failure(Some(&message_detail(object)));
    }
    let as_text = text_like(object.get("as"));
    let isp = text_like(object.get("isp"));
    let org = text_like(object.get("org"));
    row(
        "命中",
        Some(classify(&format!("{as_text} {isp} {org}"))),
        Some(&first_present(object, &["isp", "org"])),
        Some(&asn_of(&as_text)),
        None,
    )
}

fn ip_who_is(body: &str) -> Value {
    let decoded: Value = match serde_json::from_str(body) {
        Ok(value) => value,
        Err(_) => return invalid_json(),
    };
    let Some(object) = decoded.as_object() else {
        return failure(None);
    };
    if object.get("success").and_then(Value::as_bool) == Some(false) {
        return failure(Some(&message_detail(object)));
    }
    let connection = object.get("connection").and_then(Value::as_object);
    let isp = connection.map_or_else(String::new, |map| text_like(map.get("isp")));
    let org = connection.map_or_else(String::new, |map| text_like(map.get("org")));
    let domain = connection.map_or_else(String::new, |map| text_like(map.get("domain")));
    let asn_text = connection.map_or_else(String::new, |map| text_like(map.get("asn")));
    let organization = connection
        .map(|map| first_present(map, &["isp", "org"]))
        .unwrap_or_default();
    let asn = if asn_text.is_empty() {
        String::new()
    } else {
        format!("AS{asn_text}")
    };
    row(
        "命中",
        Some(classify(&format!("{isp} {org} {domain}"))),
        Some(&organization),
        Some(&asn),
        None,
    )
}

fn ip_info(body: &str) -> Value {
    let decoded: Value = match serde_json::from_str(body) {
        Ok(value) => value,
        Err(_) => return invalid_json(),
    };
    let Some(object) = decoded.as_object() else {
        return failure(None);
    };
    if let Some(error) = object.get("error") {
        if !error.is_null() {
            let detail = error
                .as_object()
                .map(|map| text_like(map.get("message")))
                .unwrap_or_default();
            return row(
                "限流",
                None,
                None,
                None,
                error.as_object().map(|_| detail.as_str()),
            );
        }
    }
    let org = text_like(object.get("org"));
    row(
        "命中",
        Some(classify(&org)),
        Some(&org_name_of(&org)),
        Some(&asn_of(&org)),
        None,
    )
}

/// Parses one source answer after the HTTP layer has seen the status code. Timeouts and socket
/// errors never reach here: those are transport facts and stay in Dart.
pub fn source_result(source: Source, http_status: i64, body: &str) -> Value {
    if http_status == 429 {
        return row("限流", None, None, None, None);
    }
    if http_status != 200 {
        return failure(Some(&format!("HTTP {http_status}")));
    }
    match source {
        Source::IpApi => ip_api(body),
        Source::IpWhoIs => ip_who_is(body),
        Source::IpInfo => ip_info(body),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn field(row: &Value, key: &str) -> String {
        row.get(key)
            .and_then(Value::as_str)
            .unwrap_or_default()
            .to_owned()
    }

    #[test]
    fn ip_api_success_uses_the_legacy_organization_chain() {
        let row = source_result(
            Source::IpApi,
            200,
            r#"{"status":"success","as":"AS15169 Google LLC","isp":"Google"}"#,
        );
        assert_eq!(field(&row, "status"), "命中");
        assert_eq!(field(&row, "ipType"), "机房");
        assert_eq!(field(&row, "organization"), "Google");
        assert_eq!(field(&row, "asn"), "AS15169");
    }

    #[test]
    fn ip_api_failure_keeps_an_empty_message_as_detail() {
        let row = source_result(Source::IpApi, 200, r#"{"status":"fail"}"#);
        assert_eq!(field(&row, "status"), "失败");
        assert_eq!(field(&row, "detail"), "");

        let row = source_result(Source::IpApi, 200, "[]");
        assert_eq!(field(&row, "status"), "失败");
        assert!(row["detail"].is_null());
    }

    #[test]
    fn ip_who_is_prefixes_the_numeric_asn() {
        let row = source_result(
            Source::IpWhoIs,
            200,
            r#"{"success":true,"connection":{"asn":15169,"isp":"Google LLC","domain":"google.com"}}"#,
        );
        assert_eq!(field(&row, "status"), "命中");
        assert_eq!(field(&row, "organization"), "Google LLC");
        assert_eq!(field(&row, "asn"), "AS15169");
        assert_eq!(field(&row, "ipType"), "机房");

        let row = source_result(
            Source::IpWhoIs,
            200,
            r#"{"success":false,"message":"bad ip"}"#,
        );
        assert_eq!(field(&row, "status"), "失败");
        assert_eq!(field(&row, "detail"), "bad ip");
    }

    #[test]
    fn ip_info_rate_limit_is_not_a_failure() {
        let row = source_result(
            Source::IpInfo,
            200,
            r#"{"error":{"message":"rate limited"}}"#,
        );
        assert_eq!(field(&row, "status"), "限流");
        assert_eq!(field(&row, "detail"), "rate limited");

        let row = source_result(Source::IpInfo, 429, "irrelevant");
        assert_eq!(field(&row, "status"), "限流");
        assert!(row["detail"].is_null());
    }

    #[test]
    fn ip_info_org_is_split_into_name_and_asn() {
        let row = source_result(Source::IpInfo, 200, r#"{"org":"AS15169 Google LLC"}"#);
        assert_eq!(field(&row, "organization"), "Google LLC");
        assert_eq!(field(&row, "asn"), "AS15169");
    }

    #[test]
    fn http_status_and_invalid_json_are_decided_here() {
        let row = source_result(Source::IpApi, 500, "oops");
        assert_eq!(field(&row, "status"), "失败");
        assert_eq!(field(&row, "detail"), "HTTP 500");

        let row = source_result(Source::IpApi, 200, "<html>");
        assert_eq!(field(&row, "detail"), "响应不是合法 JSON");
    }

    #[test]
    fn classifier_prefers_mobile_then_datacenter_then_business() {
        assert_eq!(classify("T-Mobile USA"), "移动");
        assert_eq!(classify("Amazon.com Inc."), "机房");
        assert_eq!(classify("Some Random ISP"), "商业");
        assert_eq!(classify("Some University"), "商业");
    }

    #[test]
    fn asn_and_org_helpers_match_the_dart_regex() {
        assert_eq!(asn_of("AS15169 Google LLC"), "AS15169");
        assert_eq!(asn_of("prefix AS42 suffix"), "AS42");
        assert_eq!(asn_of("AS"), "");
        assert_eq!(asn_of("no number"), "");
        assert_eq!(org_name_of("AS15169 Google LLC"), "Google LLC");
        assert_eq!(org_name_of("AS15169"), "");
        assert_eq!(org_name_of("  Google  "), "Google");
        assert_eq!(org_name_of("ASX Google"), "ASX Google");
    }
}
