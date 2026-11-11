//! HTTP status classification for a failed release query; the code maps back to the localized
//! message in Dart.

use serde_json::{json, Value};

pub fn status_message(status: i64, body: &str) -> Value {
    if status == 403 && body.contains("rate limit") {
        return json!({ "kind": "rateLimited", "status": status });
    }
    let kind = match status {
        403 => "forbidden",
        404 => "notFound",
        500.. => "serverError",
        _ => "unexpectedStatus",
    };
    json!({ "kind": kind, "status": status })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rate_limit_is_distinct_from_a_plain_403() {
        assert_eq!(
            status_message(403, "API rate limit exceeded")["kind"],
            "rateLimited"
        );
        let forbidden = status_message(403, "forbidden");
        assert_eq!(forbidden["kind"], "forbidden");
        assert_eq!(forbidden["status"], 403);
    }

    #[test]
    fn other_statuses_keep_their_code() {
        assert_eq!(status_message(404, "")["kind"], "notFound");
        assert_eq!(status_message(500, "")["kind"], "serverError");
        assert_eq!(status_message(502, "")["kind"], "serverError");
        assert_eq!(status_message(600, "")["kind"], "serverError");
        assert_eq!(status_message(418, "")["kind"], "unexpectedStatus");
        assert_eq!(status_message(418, "")["status"], 418);
    }
}
