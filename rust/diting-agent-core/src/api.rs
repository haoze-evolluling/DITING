//! OpenAI-compatible protocol layer: endpoint derivation, the request body, and the two response
//! shapes (`chat/completions`, `models`).
//!
//! The transport stays in Dart (`HttpClient`, timeouts, cancellation) because closing a socket is
//! the only way to abort a pending read. Everything that decides *what* is sent and *what the answer
//! means* is here. Failures travel back as kinds, so the sentences stay in the Dart localisation.

use serde::Serialize;
use serde_json::Value;

/// Why an endpoint could not be derived. The Dart side localises it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EndpointError {
    Empty = 0,
}

/// Which response field was missing. The Dart side localises it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ParseError {
    InvalidJson = 1,
    NotJsonObject = 2,
    EmptyContent = 3,
    NoModelListJson = 4,
    NoModelListData = 5,
    NoModels = 6,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatReply {
    pub content: String,
    pub model: String,
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub total_tokens: u32,
}

/// HTTP status becomes an actionable hint kind; the server's own sentence rides along as detail.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusKind {
    BadKey = 0,
    NoAccess = 1,
    ModelNotFound = 2,
    RateLimited = 3,
    Unavailable = 4,
    RequestFailed = 5,
}

pub const SERVER_DETAIL_LIMIT: usize = 200;

#[derive(Serialize)]
struct ChatMessage<'a> {
    role: &'a str,
    content: &'a str,
}

#[derive(Serialize)]
struct ChatBody<'a> {
    model: &'a str,
    messages: Vec<ChatMessage<'a>>,
    temperature: f64,
}

/// Base URL to `/chat/completions`; OpenAI and DeepSeek need the `/v1` segment.
pub fn chat_endpoint(raw_base_url: &str) -> Result<String, EndpointError> {
    let trimmed = raw_base_url.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return Err(EndpointError::Empty);
    }
    if trimmed.ends_with("/chat/completions") {
        return Ok(trimmed.to_string());
    }
    if trimmed.ends_with("/v1") {
        return Ok(format!("{trimmed}/chat/completions"));
    }
    if trimmed.ends_with("/api") {
        return Ok(format!("{trimmed}/v1/chat/completions"));
    }
    let lower = trimmed.to_lowercase();
    if lower == "https://api.openai.com" || lower == "https://api.deepseek.com" {
        return Ok(format!("{trimmed}/v1/chat/completions"));
    }
    Ok(format!("{trimmed}/chat/completions"))
}

pub fn models_endpoint(raw_base_url: &str) -> Result<String, EndpointError> {
    let trimmed = raw_base_url.trim().trim_end_matches('/');
    if trimmed.is_empty() {
        return Err(EndpointError::Empty);
    }
    const SUFFIX: &str = "/chat/completions";
    if let Some(stripped) = trimmed.strip_suffix(SUFFIX) {
        return Ok(format!("{stripped}/models"));
    }
    if trimmed.ends_with("/v1") {
        return Ok(format!("{trimmed}/models"));
    }
    if trimmed.ends_with("/api") {
        return Ok(format!("{trimmed}/v1/models"));
    }
    let lower = trimmed.to_lowercase();
    if lower == "https://api.openai.com" || lower == "https://api.deepseek.com" {
        return Ok(format!("{trimmed}/v1/models"));
    }
    Ok(format!("{trimmed}/models"))
}

/// The request body. A blank model falls back to `deepseek-flash`, the name the 1.4.3 build shipped
/// so a fresh dialog has something valid to send.
pub fn chat_body(model: &str, messages: &[(String, String)], temperature: f64) -> String {
    let trimmed = model.trim();
    let effective = if trimmed.is_empty() {
        "deepseek-flash"
    } else {
        trimmed
    };
    let body = ChatBody {
        model: effective,
        messages: messages
            .iter()
            .map(|(role, content)| ChatMessage { role, content })
            .collect(),
        temperature,
    };
    serde_json::to_string(&body).unwrap_or_else(|_| String::from("{}"))
}

fn usage_of(value: &Value, key: &str) -> u32 {
    value
        .get(key)
        .and_then(Value::as_f64)
        .map(|number| number as u32)
        .unwrap_or(0)
}

pub fn parse_chat(body: &str, fallback_model: &str) -> Result<ChatReply, ParseError> {
    let decoded: Value = serde_json::from_str(body).map_err(|_| ParseError::InvalidJson)?;
    let object = decoded.as_object().ok_or(ParseError::NotJsonObject)?;

    let mut content = String::new();
    if let Some(Value::Array(choices)) = object.get("choices") {
        if let Some(Value::Object(first)) = choices.first() {
            // The 1.4.3 build prefers `message.content` and only falls back to `choices[].text`
            // when `message` is missing or its `content` is not a string.
            let message_content = first
                .get("message")
                .and_then(Value::as_object)
                .and_then(|message| message.get("content"))
                .and_then(Value::as_str);
            match message_content {
                Some(text) => content = text.trim().to_string(),
                None => {
                    // Completion-style endpoints put the text in `choices[].text`.
                    if let Some(text) = first.get("text").and_then(Value::as_str) {
                        content = text.trim().to_string();
                    }
                }
            }
        }
    }
    if content.is_empty() {
        return Err(ParseError::EmptyContent);
    }

    let usage = object.get("usage");
    let read = |key: &str| usage.map(|value| usage_of(value, key)).unwrap_or(0);
    let model = match object.get("model") {
        Some(Value::String(text)) if !text.trim().is_empty() => text.trim().to_string(),
        _ => fallback_model.to_string(),
    };
    Ok(ChatReply {
        content,
        model,
        prompt_tokens: read("prompt_tokens"),
        completion_tokens: read("completion_tokens"),
        total_tokens: read("total_tokens"),
    })
}

fn compare_utf16(left: &str, right: &str) -> std::cmp::Ordering {
    left.encode_utf16().cmp(right.encode_utf16())
}

/// `data`, `models` and `result` are all accepted; ids are trimmed, de-duplicated and sorted, so the
/// picker's order does not depend on the server's.
pub fn parse_models(body: &str) -> Result<Vec<String>, ParseError> {
    let decoded: Value = serde_json::from_str(body).map_err(|_| ParseError::InvalidJson)?;
    let object = decoded.as_object().ok_or(ParseError::NoModelListJson)?;
    let array = ["data", "models", "result"]
        .iter()
        .find_map(|key| object.get(*key).filter(|value| !value.is_null()))
        .ok_or(ParseError::NoModelListData)?
        .as_array()
        .ok_or(ParseError::NoModelListData)?;

    let mut ids: Vec<String> = Vec::new();
    for item in array {
        let mut id: Option<String> = None;
        match item {
            Value::Object(entry) => {
                for key in ["id", "model_id", "name"] {
                    if let Some(Value::String(text)) = entry.get(key) {
                        if !text.trim().is_empty() {
                            id = Some(text.trim().to_string());
                            break;
                        }
                    }
                }
            }
            Value::String(text) if !text.trim().is_empty() => {
                id = Some(text.trim().to_string());
            }
            _ => {}
        }
        if let Some(id) = id {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
    }
    if ids.is_empty() {
        return Err(ParseError::NoModels);
    }
    ids.sort_by(|left, right| compare_utf16(left, right));
    Ok(ids)
}

/// Truncates to `limit` UTF-16 code units plus `…`, the unit `String.length` uses in Dart. A cut
/// through a surrogate pair leaves a replacement character; the detail only ever appears in a
/// diagnostic sentence, so that is preferable to splitting in the middle of a code point silently.
fn truncate_detail(message: &str) -> String {
    let units: Vec<u16> = message.encode_utf16().collect();
    if units.len() <= SERVER_DETAIL_LIMIT {
        return message.to_string();
    }
    let mut truncated = String::from_utf16_lossy(&units[..SERVER_DETAIL_LIMIT]);
    truncated.push('…');
    truncated
}

/// HTTP status plus the server's `error.message` becomes a kind and its detail.
pub fn describe_status(status: u16, body: &str) -> (StatusKind, Option<String>) {
    let mut server_message = String::new();
    if let Ok(Value::Object(object)) = serde_json::from_str::<Value>(body) {
        // `error.message` first, then a top-level `message`; a non-object `error` falls through.
        let from_error = object
            .get("error")
            .and_then(Value::as_object)
            .and_then(|error| error.get("message"))
            .and_then(Value::as_str);
        server_message = match from_error {
            Some(text) => text.trim().to_string(),
            None => object
                .get("message")
                .and_then(Value::as_str)
                .unwrap_or("")
                .trim()
                .to_string(),
        };
    }
    let kind = match status {
        401 => StatusKind::BadKey,
        403 => StatusKind::NoAccess,
        404 => StatusKind::ModelNotFound,
        429 => StatusKind::RateLimited,
        _ if status >= 500 => StatusKind::Unavailable,
        _ => StatusKind::RequestFailed,
    };
    let detail = (!server_message.is_empty()).then(|| truncate_detail(&server_message));
    (kind, detail)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoints_follow_the_vendor_habits() {
        assert_eq!(
            chat_endpoint("https://api.deepseek.com").unwrap(),
            "https://api.deepseek.com/v1/chat/completions"
        );
        assert_eq!(
            chat_endpoint("https://api.openai.com/v1").unwrap(),
            "https://api.openai.com/v1/chat/completions"
        );
        assert_eq!(
            chat_endpoint("https://open.bigmodel.cn/api/paas/v4").unwrap(),
            "https://open.bigmodel.cn/api/paas/v4/chat/completions"
        );
        assert_eq!(
            chat_endpoint("https://x.test/v1/chat/completions").unwrap(),
            "https://x.test/v1/chat/completions"
        );
        assert_eq!(
            chat_endpoint("  https://x.test/api/  ").unwrap(),
            "https://x.test/api/v1/chat/completions"
        );
        assert_eq!(chat_endpoint("  "), Err(EndpointError::Empty));

        assert_eq!(
            models_endpoint("https://api.deepseek.com").unwrap(),
            "https://api.deepseek.com/v1/models"
        );
        assert_eq!(
            models_endpoint("https://api.openai.com/v1/chat/completions").unwrap(),
            "https://api.openai.com/v1/models"
        );
        assert_eq!(
            models_endpoint("https://x.test/api").unwrap(),
            "https://x.test/api/v1/models"
        );
        assert_eq!(
            models_endpoint("https://x.test").unwrap(),
            "https://x.test/models"
        );
        assert_eq!(models_endpoint(""), Err(EndpointError::Empty));
    }

    #[test]
    fn request_body_matches_the_wire_shape() {
        let messages = vec![
            ("system".to_string(), "be brief".to_string()),
            ("user".to_string(), "hi".to_string()),
        ];
        let body = chat_body("test-model", &messages, 0.2);
        assert_eq!(
            body,
            "{\"model\":\"test-model\",\"messages\":[{\"role\":\"system\",\"content\":\"be brief\"},\
             {\"role\":\"user\",\"content\":\"hi\"}],\"temperature\":0.2}"
        );
        assert!(chat_body("   ", &[], 0.7).contains("\"model\":\"deepseek-flash\""));
    }

    #[test]
    fn chat_reply_reads_content_model_and_usage() {
        let body = r#"{"model":"test-model-v2","choices":[{"message":{"content":"  分析结论 "}}],
            "usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}}"#;
        let reply = parse_chat(body, "fallback").unwrap();
        assert_eq!(reply.content, "分析结论");
        assert_eq!(reply.model, "test-model-v2");
        assert_eq!(reply.prompt_tokens, 10);
        assert_eq!(reply.completion_tokens, 5);
        assert_eq!(reply.total_tokens, 15);

        // Completion-style `choices[].text`, and a missing model falls back.
        let text = parse_chat(r#"{"choices":[{"text":" hi "}]}"#, "fallback").unwrap();
        assert_eq!(text.content, "hi");
        assert_eq!(text.model, "fallback");
        assert_eq!(text.total_tokens, 0);
    }

    #[test]
    fn chat_reply_rejects_bad_shapes() {
        assert_eq!(parse_chat("not json", "m"), Err(ParseError::InvalidJson));
        assert_eq!(parse_chat("[]", "m"), Err(ParseError::NotJsonObject));
        assert_eq!(
            parse_chat(r#"{"choices":[{"message":{"content":"   "}}]}"#, "m"),
            Err(ParseError::EmptyContent)
        );
        assert_eq!(parse_chat("{}", "m"), Err(ParseError::EmptyContent));
    }

    #[test]
    fn model_list_accepts_three_shapes_and_sorts() {
        let body = r#"{"data":[{"id":"b-model"},{"id":"a-model"},{"id":"a-model"}]}"#;
        assert_eq!(parse_models(body).unwrap(), vec!["a-model", "b-model"]);

        let body = r#"{"models":["z","a"]}"#;
        assert_eq!(parse_models(body).unwrap(), vec!["a", "z"]);

        let body = r#"{"result":[{"model_id":"m2"},{"name":"m1"}]}"#;
        assert_eq!(parse_models(body).unwrap(), vec!["m1", "m2"]);
    }

    #[test]
    fn model_list_rejects_bad_shapes() {
        assert_eq!(parse_models("nope"), Err(ParseError::InvalidJson));
        assert_eq!(parse_models("[]"), Err(ParseError::NoModelListJson));
        assert_eq!(parse_models("{}"), Err(ParseError::NoModelListData));
        assert_eq!(parse_models(r#"{"data":[]}"#), Err(ParseError::NoModels));
        assert_eq!(
            parse_models(r#"{"data":[{"id":"  "},{}]}"#),
            Err(ParseError::NoModels)
        );
    }

    #[test]
    fn status_kinds_and_server_detail() {
        let (kind, detail) = describe_status(401, r#"{"error":{"message":" Invalid token "}}"#);
        assert_eq!(kind, StatusKind::BadKey);
        assert_eq!(detail.as_deref(), Some("Invalid token"));

        let (kind, detail) = describe_status(429, r#"{"message":"rate limited"}"#);
        assert_eq!(kind, StatusKind::RateLimited);
        assert_eq!(detail.as_deref(), Some("rate limited"));

        let (kind, detail) = describe_status(503, "");
        assert_eq!(kind, StatusKind::Unavailable);
        assert_eq!(detail, None);

        assert_eq!(describe_status(404, "<html>").0, StatusKind::ModelNotFound);
        assert_eq!(describe_status(403, "{}").0, StatusKind::NoAccess);
        assert_eq!(describe_status(418, "{}").0, StatusKind::RequestFailed);
    }

    #[test]
    fn server_detail_is_truncated_at_two_hundred_units() {
        let long = "x".repeat(240);
        let (_, detail) = describe_status(500, &format!(r#"{{"message":"{long}"}}"#));
        let detail = detail.expect("detail");
        assert_eq!(detail.encode_utf16().count(), SERVER_DETAIL_LIMIT + 1);
        assert!(detail.ends_with('…'));
    }
}
