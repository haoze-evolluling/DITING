use super::*;

#[test]
fn keys_match_the_go_append_order() {
    assert_eq!(
        build_key("", "com.example.app", "1.2.3.4", 443, 6, ""),
        "com.example.app|1.2.3.4|443|6"
    );
    assert_eq!(
        build_key("blk|", "com.example.app", "1.2.3.4", 443, 6, "uid_blocked"),
        "blk|com.example.app|1.2.3.4|443|6|uid_blocked"
    );
    // Empty components still produce all four separators.
    assert_eq!(build_key("", "", "", 0, 0, ""), "||0|0");
    // A reason is appended only when non-empty; a reason containing `|` is not escaped.
    assert_eq!(build_key("", "a|b", "c|d", 1, 6, "x"), "a|b|c|d|1|6|x");
}

#[test]
fn ports_and_protocols_use_plain_decimal() {
    assert_eq!(build_key("", "a", "b", 65535, 17, ""), "a|b|65535|17");
    assert_eq!(build_key("", "a", "b", -1, -2, ""), "a|b|-1|-2");
}

#[test]
fn unicode_is_preserved_byte_for_byte() {
    assert_eq!(
        build_key("", "名字", "例子.cn", 65535, 17, "原因|带竖线"),
        "名字|例子.cn|65535|17|原因|带竖线"
    );
}
