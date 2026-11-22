use super::*;

#[test]
fn csv_keeps_only_positive_integers() {
    let set = BlockedUids::parse_csv("123, 456 ,abc,-1,0,+7, ,9999999999999999999");
    assert_eq!(set.len(), 3);
    assert!(set.is_blocked(123));
    assert!(set.is_blocked(456));
    assert!(set.is_blocked(7));
    assert!(!set.is_blocked(0));
    assert!(!set.is_blocked(-1));
    assert!(!set.is_blocked(999));
}

#[test]
fn unknown_uid_is_never_blocked() {
    let set = BlockedUids::parse_csv("-1,1");
    assert!(!set.is_blocked(-1));
    assert!(set.is_blocked(1));
    assert!(BlockedUids::parse_csv("").is_empty());
}
