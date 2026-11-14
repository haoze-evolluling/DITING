//! Local HTTP API policy for the Android app (A10).
//!
//! The desktop service exposes a loopback-only HTTP API. The transport is plumbing (Kotlin/Dart's
//! `HttpServer`), but the two decisions that make it safe are policy, and live here so the server
//! cannot accidentally drift:
//!
//! * **loopback only** — the bind address *and* the client address must both be loopback. Binding
//!   `0.0.0.0` or answering a LAN client is refused, so a misconfiguration cannot expose the API to
//!   the network.
//! * **bearer token** — every request carries a token in `X-Diting-Token`; an empty expected token
//!   is treated as "not configured" and refuses everything (no unauthenticated surface).
//!
//! Route selection is a small, explicit table so an unknown path is a 404, not a fallthrough.

use std::net::IpAddr;

/// The only header the API reads.
pub const TOKEN_HEADER: &str = "X-Diting-Token";

/// Why an authorization attempt failed, or that it passed.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Decision {
    Allow,
    /// The bind or client address is not loopback.
    NotLoopback,
    /// The token is missing, empty or wrong.
    Unauthorized,
}

impl Decision {
    pub fn as_str(self) -> &'static str {
        match self {
            Decision::Allow => "allow",
            Decision::NotLoopback => "not_loopback",
            Decision::Unauthorized => "unauthorized",
        }
    }
}

/// Which read-only endpoint a request addresses.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Route {
    Status,
    Version,
}

impl Route {
    pub fn id(self) -> &'static str {
        match self {
            Route::Status => "status",
            Route::Version => "version",
        }
    }
}

/// The outcome of resolving a method + path.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum RouteOutcome {
    Found(Route),
    MethodNotAllowed,
    NotFound,
}

/// `true` for the loopback addresses the API may bind to or answer. Anything else — including a
/// non-IP string — is refused.
pub fn is_loopback_ip(text: &str) -> bool {
    match text.trim().parse::<IpAddr>() {
        Ok(address) => address.is_loopback(),
        Err(_) => false,
    }
}

/// Validates a bind address: only loopback literals are accepted, so the caller cannot open the API
/// to the LAN. The error is a stable code (`"not_loopback"` / `"invalid"`), localized by the UI.
pub fn validate_bind(bind: &str) -> Result<(), &'static str> {
    let trimmed = bind.trim();
    if trimmed.is_empty() {
        return Err("invalid");
    }
    match trimmed.parse::<IpAddr>() {
        Ok(address) if address.is_loopback() => Ok(()),
        Ok(_) => Err("not_loopback"),
        Err(_) => Err("invalid"),
    }
}

/// Constant-time equality, so a token comparison does not leak a matching prefix through timing.
fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (left, right) in a.iter().zip(b.iter()) {
        diff |= left ^ right;
    }
    diff == 0
}

/// Decides whether a request may proceed. Order matters: loopback is checked before the token so a
/// LAN client is refused without ever comparing secrets.
pub fn authorize(
    bind: &str,
    client_ip: &str,
    expected_token: &str,
    provided_token: Option<&str>,
) -> Decision {
    if validate_bind(bind).is_err() || !is_loopback_ip(client_ip) {
        return Decision::NotLoopback;
    }
    let expected = expected_token.trim();
    if expected.is_empty() {
        // No token configured means the API must stay closed, not open.
        return Decision::Unauthorized;
    }
    match provided_token.map(str::trim) {
        Some(token) if constant_time_eq(token.as_bytes(), expected.as_bytes()) => Decision::Allow,
        _ => Decision::Unauthorized,
    }
}

/// Resolves the read-only routes. Only `GET` is served; anything else on a known path is a 405.
pub fn route(method: &str, path: &str) -> RouteOutcome {
    let normalized = path.split('?').next().unwrap_or(path).trim_end_matches('/');
    let known = match normalized {
        "/status" | "/api/v1/status" => Some(Route::Status),
        "/version" | "/api/v1/version" => Some(Route::Version),
        _ => None,
    };
    match known {
        None => RouteOutcome::NotFound,
        Some(route) if method.eq_ignore_ascii_case("GET") => RouteOutcome::Found(route),
        Some(_) => RouteOutcome::MethodNotAllowed,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_loopback_binds_are_accepted() {
        assert!(validate_bind("127.0.0.1").is_ok());
        assert!(validate_bind("::1").is_ok());
        assert_eq!(validate_bind("0.0.0.0"), Err("not_loopback"));
        assert_eq!(validate_bind("192.168.1.5"), Err("not_loopback"));
        assert_eq!(validate_bind("not-an-ip"), Err("invalid"));
        assert_eq!(validate_bind(""), Err("invalid"));
    }

    #[test]
    fn a_lan_client_is_refused_even_with_the_right_token() {
        assert_eq!(
            authorize("127.0.0.1", "192.168.1.9", "secret", Some("secret")),
            Decision::NotLoopback
        );
    }

    #[test]
    fn a_missing_or_wrong_token_is_unauthorized() {
        assert_eq!(
            authorize("127.0.0.1", "127.0.0.1", "secret", None),
            Decision::Unauthorized
        );
        assert_eq!(
            authorize("127.0.0.1", "127.0.0.1", "secret", Some("wrong")),
            Decision::Unauthorized
        );
        assert_eq!(
            authorize("127.0.0.1", "127.0.0.1", "secret", Some("secret ")),
            Decision::Allow,
            "surrounding whitespace is trimmed before comparing"
        );
    }

    #[test]
    fn an_unconfigured_token_closes_the_api() {
        assert_eq!(
            authorize("127.0.0.1", "127.0.0.1", "", Some("anything")),
            Decision::Unauthorized
        );
    }

    #[test]
    fn a_non_loopback_bind_is_refused_before_the_token() {
        assert_eq!(
            authorize("0.0.0.0", "127.0.0.1", "secret", Some("secret")),
            Decision::NotLoopback
        );
    }

    #[test]
    fn routes_are_get_only_and_known_paths_only() {
        assert_eq!(route("GET", "/status"), RouteOutcome::Found(Route::Status));
        assert_eq!(
            route("get", "/api/v1/status?x=1"),
            RouteOutcome::Found(Route::Status)
        );
        assert_eq!(
            route("GET", "/version/"),
            RouteOutcome::Found(Route::Version)
        );
        assert_eq!(route("POST", "/status"), RouteOutcome::MethodNotAllowed);
        assert_eq!(route("GET", "/admin"), RouteOutcome::NotFound);
    }
}
