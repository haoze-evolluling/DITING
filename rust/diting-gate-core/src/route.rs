pub const SCOPE_APPS: &str = "apps";
pub const UID_UNKNOWN: i64 = -1;

pub fn per_app(enabled: bool, scope: &str) -> bool {
    enabled && scope == SCOPE_APPS
}

pub fn proxies_uid(enabled: bool, scope: &str, uid: i64, uids: &[i64]) -> bool {
    if !per_app(enabled, scope) {
        return true;
    }
    if uid == UID_UNKNOWN {
        return false;
    }
    uids.contains(&uid)
}

pub fn resolver_uses_proxy(enabled: bool, scope: &str) -> bool {
    !per_app(enabled, scope)
}

#[cfg(test)]
mod tests;
