use super::*;

#[test]
fn per_app_needs_enabled_and_apps_scope() {
    assert!(per_app(true, "apps"));
    assert!(!per_app(false, "apps"));
    assert!(!per_app(true, "all"));
    assert!(!per_app(false, ""));
}

#[test]
fn proxies_uid_in_apps_scope_uses_the_selected_set() {
    let uids = [10100i64, 10101];
    assert!(proxies_uid(true, "apps", 10100, &uids));
    assert!(!proxies_uid(true, "apps", 10200, &uids));
    assert!(!proxies_uid(true, "apps", UID_UNKNOWN, &uids));
    assert!(!proxies_uid(true, "apps", 0, &uids));
}

#[test]
fn proxies_uid_outside_apps_scope_proxies_everything() {
    assert!(proxies_uid(true, "all", UID_UNKNOWN, &[]));
    assert!(proxies_uid(false, "apps", UID_UNKNOWN, &[]));
}

#[test]
fn resolver_uses_proxy_unless_per_app() {
    assert!(!resolver_uses_proxy(true, "apps"));
    assert!(resolver_uses_proxy(true, "all"));
    assert!(resolver_uses_proxy(false, "apps"));
}
