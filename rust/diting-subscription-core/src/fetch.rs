//! Download policy: which addresses one update tries, in which order, when a mirror may fall back
//! to the direct address, and what a response status means. The HTTP stack and the progress
//! callback stay in Dart.

use serde_json::{json, Value};

use crate::payload;
use crate::url::{self, UrlParts};

/// Ordered attempts for one row; the last one never allows another fallback.
fn attempts(request: &Value) -> Vec<Value> {
    let record = payload::child(request, "record");
    let record_value = Value::Object(record.clone());
    let source = record
        .get("sourceType")
        .and_then(Value::as_str)
        .unwrap_or("remote");
    let remote = source != "local";
    let url = payload::text_or_empty(&record_value, "url");
    let parts = UrlParts::from(request);
    let own = if remote {
        url::mirror_url_of(
            record.get("mirrorTemplate").and_then(Value::as_str),
            &url,
            &parts,
        )
    } else {
        None
    };
    let mut targets = Vec::new();
    if let Some(own) = own {
        let fallback = payload::flag_or(&record_value, "mirrorFallback", true);
        targets.push(json!({
            "url": own,
            "usedMirror": true,
            "allowFallback": fallback,
        }));
        if fallback {
            targets.push(json!({ "url": url, "usedMirror": false, "allowFallback": false }));
        }
        return targets;
    }
    let global = if remote {
        url::mirror_url_of(
            request.get("globalTemplate").and_then(Value::as_str),
            &url,
            &parts,
        )
    } else {
        None
    };
    if let Some(global) = global {
        // A row without its own template always falls back to the direct address.
        targets.push(json!({
            "url": global,
            "usedMirror": true,
            "allowFallback": true,
        }));
    }
    targets.push(json!({ "url": url, "usedMirror": false, "allowFallback": false }));
    targets
}

pub fn targets(request: &Value) -> Value {
    json!({ "targets": attempts(request) })
}

/// What to do with one response: `retry` drops the validators and asks again, `content` reads the
/// body, `notModified` keeps the stored rules and `failed` carries the status.
///
/// A 412 only retries while validators were actually sent; otherwise it is a plain failure.
pub fn verdict(request: &Value) -> Value {
    let Some(status) = payload::integer(request, "status") else {
        return json!({ "kind": "failed", "status": 0 });
    };
    let use_validators = payload::flag_or(request, "useValidators", true);
    let kind = if status == 412 && use_validators {
        "retry"
    } else if status == 304 {
        "notModified"
    } else if !(200..300).contains(&status) {
        "failed"
    } else {
        "content"
    };
    json!({ "kind": kind, "status": status })
}

/// Validator headers for the request; an empty or missing value sends nothing.
pub fn headers(request: &Value) -> Value {
    let mut answer = serde_json::Map::new();
    if !payload::flag_or(request, "useValidators", true) {
        return Value::Object(answer);
    }
    if let Some(etag) = payload::text(request, "etag").filter(|value| !value.is_empty()) {
        answer.insert("ifNoneMatch".to_owned(), Value::String(etag));
    }
    if let Some(modified) = payload::text(request, "lastModified").filter(|value| !value.is_empty())
    {
        answer.insert("ifModifiedSince".to_owned(), Value::String(modified));
    }
    Value::Object(answer)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn request(own: Option<&str>, fallback: bool, global: Option<&str>) -> Value {
        json!({
            "record": {
                "url": "https://example.com/rules.txt",
                "sourceType": "remote",
                "mirrorTemplate": own,
                "mirrorFallback": fallback,
            },
            "globalTemplate": global,
            "urlParts": {
                "parsed": true, "hasScheme": true, "scheme": "https",
                "host": "example.com", "path": "/rules.txt", "query": ""
            },
        })
    }

    #[test]
    fn own_mirror_precedes_global_and_direct() {
        let answer = targets(&request(
            Some("https://m/{url}"),
            true,
            Some("https://g/{url}"),
        ));
        let list = answer["targets"].as_array().unwrap();
        assert_eq!(list.len(), 2);
        assert_eq!(
            list[0]["url"],
            json!("https://m/https://example.com/rules.txt")
        );
        assert_eq!(list[0]["allowFallback"], json!(true));
        assert_eq!(list[1]["url"], json!("https://example.com/rules.txt"));
        assert_eq!(list[1]["allowFallback"], json!(false));
    }

    #[test]
    fn own_mirror_without_fallback_never_goes_direct() {
        let answer = targets(&request(Some("https://m/{url}"), false, None));
        assert_eq!(answer["targets"].as_array().unwrap().len(), 1);
        assert_eq!(answer["targets"][0]["allowFallback"], json!(false));
    }

    #[test]
    fn global_mirror_always_falls_back() {
        let answer = targets(&request(None, false, Some("https://g/{url}")));
        let list = answer["targets"].as_array().unwrap();
        assert_eq!(list[0]["allowFallback"], json!(true));
        assert_eq!(list[1]["url"], json!("https://example.com/rules.txt"));
    }

    #[test]
    fn a_broken_template_is_skipped() {
        let answer = targets(&request(Some("ftp://m/{url}"), true, None));
        assert_eq!(answer["targets"].as_array().unwrap().len(), 1);
    }

    #[test]
    fn status_verdicts() {
        let verdict_of = |status: i64, validators: bool| {
            verdict(&json!({ "status": status, "useValidators": validators }))["kind"]
                .as_str()
                .unwrap()
                .to_owned()
        };
        assert_eq!(verdict_of(412, true), "retry");
        assert_eq!(verdict_of(412, false), "failed");
        assert_eq!(verdict_of(304, true), "notModified");
        assert_eq!(verdict_of(304, false), "notModified");
        assert_eq!(verdict_of(200, true), "content");
        assert_eq!(verdict_of(204, false), "content");
        assert_eq!(verdict_of(500, true), "failed");
    }

    #[test]
    fn validators_are_optional() {
        assert_eq!(
            headers(&json!({ "etag": "", "lastModified": null, "useValidators": true })),
            json!({})
        );
        assert_eq!(
            headers(&json!({
                "etag": "abc", "lastModified": "yesterday", "useValidators": true
            })),
            json!({ "ifNoneMatch": "abc", "ifModifiedSince": "yesterday" })
        );
        assert_eq!(
            headers(&json!({ "etag": "abc", "useValidators": false })),
            json!({})
        );
    }
}
