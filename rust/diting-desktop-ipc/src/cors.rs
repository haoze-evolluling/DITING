use hyper::header::{
    HeaderMap, HeaderValue, ACCESS_CONTROL_ALLOW_HEADERS, ACCESS_CONTROL_ALLOW_METHODS,
    ACCESS_CONTROL_ALLOW_ORIGIN, ACCESS_CONTROL_MAX_AGE,
};
use hyper::http::HeaderName;

pub const ALLOW_PRIVATE_NETWORK: &str = "access-control-allow-private-network";

pub fn is_trusted_origin(origin: &str, host: Option<&str>) -> bool {
    let origin = origin.trim();
    if origin.is_empty() {
        return true;
    }
    // Tauri serves the desktop client from a reserved custom-protocol origin.
    // A regular web page cannot forge either scheme, so these stay local-only.
    if origin.eq_ignore_ascii_case("tauri://localhost") {
        return true;
    }
    let Some(rest) = origin
        .strip_prefix("http://")
        .or_else(|| origin.strip_prefix("https://"))
    else {
        return false;
    };
    let authority = rest.split('/').next().unwrap_or(rest);
    let authority = authority.rsplit('@').next().unwrap_or(authority);
    let hostname = authority_host(authority);
    if hostname.is_empty() {
        return false;
    }
    if hostname.eq_ignore_ascii_case("localhost")
        || hostname.eq_ignore_ascii_case("tauri.localhost")
    {
        return true;
    }
    if let Ok(ip) = hostname
        .trim_matches(['[', ']'])
        .parse::<std::net::IpAddr>()
    {
        if ip.is_loopback() {
            return true;
        }
    }
    match host {
        Some(host) => {
            authority.trim_start_matches('[').eq_ignore_ascii_case(host)
                || authority.eq_ignore_ascii_case(host)
        }
        None => false,
    }
}

fn authority_host(authority: &str) -> String {
    if let Some(rest) = authority.strip_prefix('[') {
        if let Some((host, _)) = rest.split_once(']') {
            return host.to_string();
        }
    }
    match authority.rsplit_once(':') {
        Some((host, port)) if port.chars().all(|ch| ch.is_ascii_digit()) => host.to_string(),
        _ => authority.to_string(),
    }
}

pub fn apply_headers(headers: &mut HeaderMap, origin: &str, host: Option<&str>) {
    let trusted = is_trusted_origin(origin, host);
    if origin.trim().is_empty() {
        headers.insert(ACCESS_CONTROL_ALLOW_ORIGIN, HeaderValue::from_static("*"));
    } else if trusted {
        if let Ok(value) = HeaderValue::from_str(origin.trim()) {
            headers.insert(ACCESS_CONTROL_ALLOW_ORIGIN, value);
            headers.insert(hyper::header::VARY, HeaderValue::from_static("Origin"));
            headers.insert(
                hyper::header::ACCESS_CONTROL_ALLOW_CREDENTIALS,
                HeaderValue::from_static("true"),
            );
        }
    }
    headers.insert(
        ACCESS_CONTROL_ALLOW_METHODS,
        HeaderValue::from_static("GET, POST, PUT, DELETE, OPTIONS, HEAD"),
    );
    headers.insert(
        HeaderName::from_static(ALLOW_PRIVATE_NETWORK),
        HeaderValue::from_static("true"),
    );
    headers.insert(ACCESS_CONTROL_MAX_AGE, HeaderValue::from_static("86400"));
    headers.insert(
        ACCESS_CONTROL_ALLOW_HEADERS,
        HeaderValue::from_static(
            "Content-Type, Authorization, X-API-Token, Accept, Origin, Cache-Control, X-Requested-With, Access-Control-Request-Private-Network",
        ),
    );
}

pub fn preflight_status(origin: &str, host: Option<&str>) -> Option<u16> {
    if is_trusted_origin(origin, host) {
        Some(204)
    } else {
        Some(403)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn internet_origins_are_rejected() {
        assert!(!is_trusted_origin(
            "https://evil.example",
            Some("127.0.0.1:15353")
        ));
        assert!(!is_trusted_origin("null", None));
    }

    #[test]
    fn loopback_and_same_origin_are_trusted() {
        assert!(is_trusted_origin("", None));
        assert!(is_trusted_origin("http://localhost:3000", None));
        assert!(is_trusted_origin("http://127.0.0.1:8080", None));
        assert!(is_trusted_origin("http://[::1]:8080", None));
        assert!(is_trusted_origin(
            "http://127.0.0.1:15353",
            Some("127.0.0.1:15353")
        ));
    }

    #[test]
    fn tauri_client_origins_are_trusted() {
        assert!(is_trusted_origin("tauri://localhost", None));
        assert!(is_trusted_origin("http://tauri.localhost", None));
        assert!(is_trusted_origin("https://tauri.localhost", None));
        assert!(!is_trusted_origin("tauri://evil.example", None));
    }

    #[test]
    fn preflight_rejects_untrusted_origins() {
        assert_eq!(preflight_status("https://evil.example", None), Some(403));
        assert_eq!(preflight_status("http://localhost:3000", None), Some(204));
    }
}
