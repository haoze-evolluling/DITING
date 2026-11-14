//! HTTP `Alt-Svc` negotiation for DoH3 (N7).
//!
//! A DoH response may advertise an HTTP/3 endpoint through `Alt-Svc: h3=":443"; ma=86400`. Acting on
//! it means two decisions applied on every query, so they live here as one pure implementation:
//! parse the header into an [`AltSvc`], and decide whether the next query should prefer HTTP/3 or
//! stay on HTTP/2 (with a bounded failure count so a broken H3 path cannot pin every query).

/// An HTTP/3 alternative endpoint advertised by a DoH server.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AltSvc {
    /// The HTTP/3 ALPN token that matched (`h3`, `h3-29`, …). Only the `h3` family is accepted.
    pub protocol: String,
    /// The advertised authority port (defaults to 443 when the value is just `:port`).
    pub port: u16,
    /// `ma=` lifetime in seconds; 0 when absent (the caller then treats it as a one-shot hint).
    pub max_age: u64,
}

/// Whether to attempt HTTP/3 or fall back to DoH/HTTP-2 for the next query.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Transport {
    Doh3,
    Doh,
}

/// The chosen primary transport and the one to use when it fails.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Plan {
    pub prefer: Transport,
    pub fallback: Transport,
}

/// Parses an `Alt-Svc` header value, returning the first advertised `h3` endpoint.
///
/// Entries are comma-separated; each looks like `h3=":443"` or `h3="alt.example:443"; ma=86400`. A
/// protocol other than the `h3` family (`h2`, `h3-29` is accepted as `h3`) is ignored. A relative
/// value (`":443"`, meaning "same host, this port") is accepted; an absolute authority keeps only its
/// port here (the host is the DoH host).
pub fn parse_alt_svc(header: &str) -> Option<AltSvc> {
    for entry in header.split(',') {
        let mut parts = entry.split(';');
        let head = parts.next().unwrap_or("").trim();
        let Some((token, value)) = head.split_once('=') else {
            continue;
        };
        let token = token.trim();
        if !(token == "h3" || token.starts_with("h3-")) {
            continue;
        }
        let authority = value.trim().trim_matches('"');
        let port = authority
            .rsplit(':')
            .next()
            .and_then(|p| p.parse::<u16>().ok());
        let Some(port) = port else {
            continue;
        };
        let mut max_age = 0u64;
        for parameter in parts {
            let parameter = parameter.trim();
            if let Some(age) = parameter.strip_prefix("ma=") {
                max_age = age.trim().parse::<u64>().unwrap_or(0);
            }
        }
        return Some(AltSvc {
            protocol: token.to_string(),
            port,
            max_age,
        });
    }
    None
}

/// Chooses the next transport.
///
/// HTTP/3 is preferred only when it is enabled, the server advertised it, and it has not failed more
/// than `max_failures` times in a row. The fallback is always DoH/HTTP-2, so a bad advertisement can
/// never make a provider unusable.
pub fn plan(
    enabled: bool,
    alt: Option<&AltSvc>,
    consecutive_failures: u32,
    max_failures: u32,
) -> Plan {
    let prefer = if enabled && alt.is_some() && consecutive_failures < max_failures {
        Transport::Doh3
    } else {
        Transport::Doh
    };
    Plan {
        prefer,
        fallback: Transport::Doh,
    }
}

/// DoH3 and DoH must return the same DNS message for the same query; the caller compares the wire
/// bytes and, on mismatch, keeps the DoH answer (the proven transport).
pub fn answers_agree(doh3: &[u8], doh: &[u8]) -> bool {
    doh3 == doh
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_a_relative_h3_authority() {
        assert_eq!(
            parse_alt_svc("h3=\":443\"; ma=86400"),
            Some(AltSvc {
                protocol: "h3".into(),
                port: 443,
                max_age: 86400
            })
        );
    }

    #[test]
    fn parses_the_first_h3_entry_among_others() {
        let header = "h2=\":443\", h3-29=\":8443\"; ma=60";
        assert_eq!(
            parse_alt_svc(header),
            Some(AltSvc {
                protocol: "h3-29".into(),
                port: 8443,
                max_age: 60
            })
        );
    }

    #[test]
    fn ignores_headers_without_h3() {
        assert_eq!(parse_alt_svc("h2=\":443\""), None);
        assert_eq!(parse_alt_svc(""), None);
    }

    #[test]
    fn prefers_doh3_only_when_enabled_advertised_and_healthy() {
        let alt = AltSvc {
            protocol: "h3".into(),
            port: 443,
            max_age: 0,
        };
        assert_eq!(plan(true, Some(&alt), 0, 3).prefer, Transport::Doh3);
        assert_eq!(plan(false, Some(&alt), 0, 3).prefer, Transport::Doh);
        assert_eq!(plan(true, None, 0, 3).prefer, Transport::Doh);
        assert_eq!(plan(true, Some(&alt), 3, 3).prefer, Transport::Doh);
        // The fallback is always DoH so a bad H3 path cannot brick the provider.
        assert_eq!(plan(true, Some(&alt), 0, 3).fallback, Transport::Doh);
    }

    #[test]
    fn answer_agreement_is_exact() {
        assert!(answers_agree(b"answer", b"answer"));
        assert!(!answers_agree(b"answer", b"other"));
    }
}
