//! ClientID extraction and DoH path normalisation.
//!
//! A ClientID is a stable identity a client puts into the encrypted entry point: the first label of
//! `<ClientID>.<server_name>` on DoT/DoQ, or a trailing path segment on DoH. It survives an IP
//! change, which is why it takes precedence over the IP-based group. The validation mirrors
//! `client_id.go`: a single DNS label, 63 bytes, ASCII alphanumerics with hyphens only inside.

/// Single DNS label limit (RFC 1035).
const MAX_CLIENT_ID_LEN: usize = 63;
const DEFAULT_DOH_PATH: &str = "/dns-query";

/// Normalises a configured DoH path the way `normalizeDoHPath` did.
///
/// The result always starts with `/`, has no trailing slash, no template placeholders and none of
/// the characters that conflict with route patterns. An empty path, `/`, or a path that cleans to
/// nothing falls back to `/dns-query`.
pub fn normalize_doh_path(path: &str) -> String {
    let trimmed = path.trim();
    if trimmed.is_empty() || trimmed == "/" {
        return DEFAULT_DOH_PATH.to_string();
    }
    let mut value = if trimmed.starts_with('/') {
        trimmed.to_string()
    } else {
        format!("/{trimmed}")
    };
    value = value.trim_end_matches('/').to_string();
    if value.is_empty() {
        return DEFAULT_DOH_PATH.to_string();
    }
    value = strip_doh_template(&value);
    value = clean_path(&value);
    if value == "/" || value == "." {
        return DEFAULT_DOH_PATH.to_string();
    }
    value = sanitize_path(&value);
    if value.is_empty() || value == "/" {
        return DEFAULT_DOH_PATH.to_string();
    }
    value
}

/// Removes `{...}` placeholders (for example DDR's `{?dns}`) before the path is cleaned.
fn strip_doh_template(path: &str) -> String {
    let mut value = path.to_string();
    loop {
        let Some(start) = value.find('{') else {
            return value;
        };
        match value[start..].find('}') {
            Some(end) => value = format!("{}{}", &value[..start], &value[start + end + 1..]),
            None => return value[..start].to_string(),
        }
    }
}

/// `path.Clean` for slash-separated paths.
fn clean_path(path: &str) -> String {
    let rooted = path.starts_with('/');
    let mut stack: Vec<&str> = Vec::new();
    for segment in path.split('/') {
        match segment {
            "" | "." => {}
            ".." => match stack.last() {
                Some(last) if *last != ".." => {
                    stack.pop();
                }
                _ if !rooted => stack.push(".."),
                _ => {}
            },
            other => stack.push(other),
        }
    }
    if stack.is_empty() {
        return if rooted {
            "/".to_string()
        } else {
            ".".to_string()
        };
    }
    let joined = stack.join("/");
    if rooted {
        format!("/{joined}")
    } else {
        joined
    }
}

/// Replaces characters that would break a route pattern or a URL.
fn sanitize_path(path: &str) -> String {
    path.chars()
        .map(|character| match character {
            '{' | '}' => '-',
            character if character < '\u{20}' || character == '\u{7f}' => '-',
            character => character,
        })
        .collect()
}

/// Validates a ClientID label and returns its lowercase form.
pub(crate) fn validate_client_id(value: &str) -> Option<String> {
    let label = value.trim();
    let bytes = label.as_bytes();
    if bytes.is_empty() || bytes.len() > MAX_CLIENT_ID_LEN {
        return None;
    }
    for (index, byte) in bytes.iter().enumerate() {
        if byte.is_ascii_alphanumeric() {
            continue;
        }
        if *byte == b'-' && index > 0 && index + 1 < bytes.len() {
            continue;
        }
        return None;
    }
    Some(label.to_ascii_lowercase())
}

/// `ClientIDFromServerName`: extracts the immediate subdomain label of the configured name.
///
/// `cli_name` is the SNI (DoT/DoQ) or the request host (DoH). Only one extra label is accepted;
/// deeper names are not treated as an identity the client did not declare.
pub fn client_id_from_server_name(cli_name: &str, server_name: &str) -> Option<String> {
    let host = normalize_server_name(server_name);
    let client = normalize_server_name(cli_name);
    if host.is_empty() || client.is_empty() || client == host {
        return None;
    }
    let tail = format!(".{host}");
    let prefix = client.strip_suffix(&tail)?;
    if prefix.is_empty() || prefix.contains('.') {
        return None;
    }
    validate_client_id(prefix)
}

fn normalize_server_name(name: &str) -> String {
    let trimmed = name.trim();
    let trimmed = trimmed.strip_suffix('.').unwrap_or(trimmed);
    trimmed.to_ascii_lowercase()
}

/// `clientIDFromPath`: the DoH rule. The request path must be the configured path plus exactly one
/// trailing segment; that segment is validated and lowercased.
pub fn client_id_from_path(path: &str, doh_path: &str) -> Option<String> {
    let base = normalize_doh_path(doh_path);
    match path_segment_after(path, &base) {
        Some(segment) => validate_client_id(segment),
        None => None,
    }
}

/// Returns the single trailing segment when `path` is `<base>/<segment>`.
pub(crate) fn path_segment_after<'a>(path: &'a str, base: &str) -> Option<&'a str> {
    let rest = path.strip_prefix(base)?;
    let segment = rest.strip_prefix('/')?;
    if segment.is_empty() || segment.contains('/') {
        return None;
    }
    Some(segment)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn paths_are_normalised_like_go() {
        assert_eq!(normalize_doh_path(""), "/dns-query");
        assert_eq!(normalize_doh_path("   "), "/dns-query");
        assert_eq!(normalize_doh_path("/"), "/dns-query");
        assert_eq!(normalize_doh_path("dns-query"), "/dns-query");
        assert_eq!(normalize_doh_path("/dns-query/"), "/dns-query");
        assert_eq!(normalize_doh_path("/dns-query///"), "/dns-query");
        assert_eq!(normalize_doh_path("//dns-query"), "/dns-query");
        assert_eq!(normalize_doh_path("/dns-query/../foo"), "/foo");
        assert_eq!(normalize_doh_path("/dns-query{?dns}"), "/dns-query");
        assert_eq!(normalize_doh_path("/a b"), "/a b");
    }

    #[test]
    fn template_is_stripped_before_cleaning() {
        assert_eq!(strip_doh_template("/dns-query{?dns}"), "/dns-query");
        assert_eq!(strip_doh_template("/dns{query"), "/dns");
    }

    #[test]
    fn server_name_accepts_only_an_immediate_subdomain() {
        assert_eq!(
            client_id_from_server_name("phone.dns.lan", "dns.lan"),
            Some("phone".to_string())
        );
        assert_eq!(
            client_id_from_server_name("PHONE.DNS.LAN.", "dns.lan."),
            Some("phone".to_string())
        );
        assert_eq!(client_id_from_server_name("dns.lan", "dns.lan"), None);
        assert_eq!(client_id_from_server_name("a.b.dns.lan", "dns.lan"), None);
        assert_eq!(client_id_from_server_name("other.lan", "dns.lan"), None);
        assert_eq!(client_id_from_server_name("-bad.dns.lan", "dns.lan"), None);
        assert_eq!(client_id_from_server_name("bad-.dns.lan", "dns.lan"), None);
    }

    #[test]
    fn path_rule_takes_one_segment() {
        assert_eq!(
            client_id_from_path("/dns-query/laptop", "/dns-query"),
            Some("laptop".to_string())
        );
        assert_eq!(
            client_id_from_path("/dns-query/LAPTOP/", "/dns-query"),
            None
        );
        assert_eq!(client_id_from_path("/dns-query", "/dns-query"), None);
        assert_eq!(client_id_from_path("/dns-query/", "/dns-query"), None);
        assert_eq!(client_id_from_path("/dns-query/a/b", "/dns-query"), None);
        assert_eq!(client_id_from_path("/dns-query/bad!", "/dns-query"), None);
        assert_eq!(client_id_from_path("/other/laptop", "/dns-query"), None);
    }
}
