//! The cache/transport constants shared with Dart; a second copy in Dart would let the cache keys
//! or the size limits drift.

use serde_json::{json, Value};

pub fn plan() -> Value {
    json!({
        "container": "recognition_members",
        "configKey": "config_json",
        "savedAtKey": "saved_at_ms",
        "etagKey": "etag",
        "membersUrl": "https://raw.githubusercontent.com/haoze-evolluling/DITING/main/recognition_members.json",
        "avatarBaseUrl": "https://raw.githubusercontent.com/haoze-evolluling/DITING/main/avatars/",
        "maxConfigBytes": 262144,
        "maxAvatarBytes": 1048576,
        "refreshAttempts": 3,
        "refreshDelayBaseMs": 400,
        "avatarAttempts": 3,
        "avatarDelayBaseMs": 300,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn limits_and_keys_match_the_legacy_cache() {
        let plan = plan();
        assert_eq!(plan["container"], "recognition_members");
        assert_eq!(plan["configKey"], "config_json");
        assert_eq!(plan["savedAtKey"], "saved_at_ms");
        assert_eq!(plan["etagKey"], "etag");
        assert_eq!(plan["maxConfigBytes"], 256 * 1024);
        assert_eq!(plan["maxAvatarBytes"], 1024 * 1024);
        assert_eq!(plan["refreshAttempts"], 3);
        assert_eq!(plan["avatarAttempts"], 3);
    }
}
