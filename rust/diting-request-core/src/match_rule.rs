use diting_go_compat::netaddr::split_host_port;
use diting_go_compat::text::{go_lower, go_trim_space};

use crate::rules::Rule;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Decision {
    pub matched: bool,
    pub blocked: bool,
    pub pattern: String,
    pub domain_host: String,
}

pub fn decide(rules: &[Rule], scheme: &str, host: &str, path: &str) -> Decision {
    let mut folded = go_lower(go_trim_space(host)).into_owned();
    if let Ok((parsed_host, port)) = split_host_port(&folded) {
        if (scheme == "http" && port == "80") || (scheme == "https" && port == "443") {
            folded = parsed_host.to_string();
        }
    }

    let path = if path.is_empty() { "/" } else { path };
    let url = go_lower(&format!("{scheme}://{folded}{path}")).into_owned();

    let mut best: Option<(usize, usize)> = None;
    let mut best_allow = false;
    for (index, rule) in rules.iter().enumerate() {
        if !url.starts_with(&rule.pattern) {
            continue;
        }
        let length = rule.pattern.len();
        let better = match best {
            None => true,
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
