//! The outbound proxy scope: `perApp` and `proxiesUID`.
//!
//! The configuration itself is normalized by `diting-proxy-core`; this is the per-flow decision
//! built on top of it. `enabled && scope == "apps"` means only the selected UIDs are proxied;
//! everything else (including the engine's own DNS dials and flows whose owner cannot be
//! resolved) stays direct.

/// `outboundScopeApps`.
pub const SCOPE_APPS: &str = "apps";
/// `UIDUnknown`.
pub const UID_UNKNOWN: i64 = -1;

/// `perApp`: the proxy only applies to the selected UIDs.
pub fn per_app(enabled: bool, scope: &str) -> bool {
    enabled && scope == SCOPE_APPS
}

/// `proxiesUID`: whether a flow owned by `uid` uses the proxy.
///
/// In `all` scope every flow (and the engine's own DNS dials) uses it. In `apps` scope an
/// unattributable flow stays direct, so an unselected app is never pushed into the proxy.
pub fn proxies_uid(enabled: bool, scope: &str, uid: i64, uids: &[i64]) -> bool {
    if !per_app(enabled, scope) {
        return true;
    }
    if uid == UID_UNKNOWN {
        return false;
    }
    uids.contains(&uid)
}

/// `resolverOutbound`: the engine's own DNS dials are direct in per-app mode.
pub fn resolver_uses_proxy(enabled: bool, scope: &str) -> bool {
    !per_app(enabled, scope)
}

#[cfg(test)]
mod tests;
