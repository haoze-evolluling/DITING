use std::panic::{catch_unwind, AssertUnwindSafe};

use jni::objects::{JObject, JString};
use jni::sys::{jint, jstring};
use jni::JNIEnv;
use serde_json::{json, Value};

use diting_dns_core::RewriteTable;
use diting_policy_core::json::RuleSnapshot;
use diting_policy_core::Snapshot;

use super::{answer, text};

#[derive(Debug, PartialEq, Eq)]
pub struct CheckOutcome {
    pub action: &'static str,
    pub blocked: bool,
    pub reason: String,
    pub rewrite: Option<Value>,
}

fn evaluate_check(
    snapshot_json: &str,
    rewrite_json: &str,
    domain: &str,
    app: &str,
    qtype: u16,
) -> Result<CheckOutcome, String> {
    let request = RuleSnapshot::parse(snapshot_json.as_bytes())
        .map_err(|error| format!("parse rule snapshot: {error}"))?;
    let snapshot = Snapshot::build(&request);
    let answer = snapshot.answer_uncached(domain, app, qtype);
    let action = if answer.reason.as_str() == "__ALLOW__" {
        "allow"
    } else if answer.blocked {
        "block"
    } else {
        "pass"
    };
    Ok(CheckOutcome {
        action,
        blocked: answer.blocked,
        reason: answer.reason.as_str().to_string(),
        rewrite: rewrite_entry(rewrite_json, domain),
    })
}

fn rewrite_entry(rewrite_json: &str, domain: &str) -> Option<Value> {
    if rewrite_json.trim().is_empty() {
        return None;
    }
    let entries = crate::policy::rewrites_from_json(rewrite_json).ok()?;
    let table = RewriteTable::build(&entries);
    let entry = table.lookup(domain)?;
    if entry.is_empty() {
        return None;
    }
    Some(json!({
        "cname": entry.cname,
        "ip4": entry.ip4,
        "ip6": entry.ip6,
    }))
}

fn outcome_json(outcome: &CheckOutcome) -> String {
    json!({
        "action": outcome.action,
        "blocked": outcome.blocked,
        "reason": outcome.reason,
        "rewrite": outcome.rewrite,
    })
    .to_string()
}

#[no_mangle]
pub extern "system" fn Java_com_haoze_diting_engine_RuleTestNative_check(
    mut env: JNIEnv<'_>,
    _class: JObject<'_>,
    snapshot_json: JString<'_>,
    rewrite_json: JString<'_>,
    domain: JString<'_>,
    app: JString<'_>,
    qtype: jint,
) -> jstring {
    let snapshot_json = text(&mut env, &snapshot_json);
    let rewrite_json = text(&mut env, &rewrite_json);
    let domain = text(&mut env, &domain);
    let app = text(&mut env, &app);
    let qtype = u16::try_from(qtype).unwrap_or(0);

    let result = catch_unwind(AssertUnwindSafe(|| {
        evaluate_check(&snapshot_json, &rewrite_json, &domain, &app, qtype)
    }));
    match result {
        Ok(Ok(outcome)) => answer(&env, Some(outcome_json(&outcome))),
        Ok(Err(message)) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                format!("rule test: {message}"),
            );
            std::ptr::null_mut()
        }
        Err(_) => {
            let _ = env.throw_new(
                "java/lang/IllegalStateException",
                "rule test panicked; see logcat",
            );
            std::ptr::null_mut()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SNAPSHOT: &str = r#"{
        "globalBlock": ["ads.example.com", "*.tracker.net"],
        "globalAllow": ["keep.example.com"],
        "specialBlock": [{"pattern": "q.example.com", "dnsType": "AAAA"}]
    }"#;

    fn check(domain: &str, qtype: u16) -> CheckOutcome {
        evaluate_check(SNAPSHOT, "", domain, "", qtype).expect("valid snapshot")
    }

    #[test]
    fn block_allow_and_pass_are_distinguished() {
        let blocked = check("ads.example.com", 1);
        assert_eq!(blocked.action, "block");
        assert!(blocked.blocked);
        assert_eq!(blocked.reason, "ads.example.com");

        let allowed = check("keep.example.com", 1);
        assert_eq!(allowed.action, "allow");
        assert!(!allowed.blocked);
        assert_eq!(allowed.reason, "__ALLOW__");

        let passed = check("other.example.com", 1);
        assert_eq!(passed.action, "pass");
        assert_eq!(passed.reason, "");
    }

    #[test]
    fn the_qtype_modifier_is_honoured() {
        assert_eq!(check("q.example.com", 28).action, "block");
        assert_eq!(check("q.example.com", 1).action, "pass");
    }

    #[test]
    fn a_rewrite_entry_is_reported() {
        let outcome = evaluate_check(
            SNAPSHOT,
            r#"{"www.example.com": "1.2.3.4"}"#,
            "www.example.com",
            "",
            1_u16,
        )
        .expect("valid");
        let rewrite = outcome.rewrite.expect("rewrite match");
        assert_eq!(rewrite["ip4"], json!("1.2.3.4"));
        assert_eq!(rewrite["cname"], json!(""));
    }

    #[test]
    fn a_malformed_snapshot_is_an_error() {
        assert!(evaluate_check("not json", "", "x.com", "", 1).is_err());
    }

    #[test]
    fn out_of_range_qtype_is_no_restriction() {
        let outcome = evaluate_check(SNAPSHOT, "", "q.example.com", "", 0).expect("valid");
        assert_eq!(outcome.action, "pass");
    }
}
