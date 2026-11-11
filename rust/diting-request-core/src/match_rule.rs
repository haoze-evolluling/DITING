//! The per-request decision: URL construction, the longest-prefix walk and the fallback host.
//!
//! The order matters and is reproduced as-is:
//!
//! 1. `host = strings.ToLower(strings.TrimSpace(host))`;
//! 2. when `net.SplitHostPort` succeeds **and** the scheme is exactly `http`/`https` (no case fold)
//!    with port `80`/`443`, the host becomes the parsed one — so an upper-case scheme keeps its
//!    `:443` and the built URL stops matching;
//! 3. `path == ""` becomes `/`;
//! 4. `url = strings.ToLower(scheme + "://" + host + path)`, so the path is lower-cased too;
//! 5. the longest matching pattern wins, and an `allow` wins a tie;
//! 6. when nothing matched, the domain-rule fallback is asked about the host with its port stripped.

use diting_go_compat::netaddr::split_host_port;
use diting_go_compat::text::{go_lower, go_trim_space};

use crate::rules::Rule;

/// What one request evaluates to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Decision {
    /// True when a rule pattern was a prefix of the request URL.
    pub matched: bool,
    /// True when the winning rule is a `block` rule.
    pub blocked: bool,
    /// The winning pattern, empty when nothing matched.
    pub pattern: String,
    /// The host the domain-rule fallback should evaluate (port stripped).
    pub domain_host: String,
}

/// Decides one request. `rules` must already be normalized ([`crate::rules::normalize_all`]).
pub fn decide(rules: &[Rule], scheme: &str, host: &str, path: &str) -> Decision {
    let mut folded = go_lower(go_trim_space(host)).into_owned();
    if let Ok((parsed_host, port)) = split_host_port(&folded) {
        if (scheme == "http" && port == "80") || (scheme == "https" && port == "443") {
            folded = parsed_host.to_string();
        }
    }

    let path = if path.is_empty() { "/" } else { path };
    let url = go_lower(&format!("{scheme}://{folded}{path}")).into_owned();

    let mut best: Option<(usize, usize)> = None; // (pattern length, rule index)
    let mut best_allow = false;
    for (index, rule) in rules.iter().enumerate() {
        if !url.starts_with(&rule.pattern) {
            continue;
        }
        let length = rule.pattern.len();
        let better = match best {
            None => true,
            // A longer prefix wins; at equal length an `allow` wins, and the first one wins the rest.
            Some((best_length, _)) => {
                length > best_length || (length == best_length && rule.allow && !best_allow)
            }
        };
        if better {
            best = Some((length, index));
            best_allow = rule.allow;
        }
    }

    let domain_host = match split_host_port(&folded) {
        Ok((parsed_host, _port)) => parsed_host.to_string(),
        Err(_) => folded,
    };

    match best {
        Some((_, index)) => Decision {
            matched: true,
            blocked: !best_allow,
            pattern: rules[index].pattern.clone(),
            domain_host,
        },
        None => Decision {
            matched: false,
            blocked: false,
            pattern: String::new(),
            domain_host,
        },
    }
}

#[cfg(test)]
mod tests;
