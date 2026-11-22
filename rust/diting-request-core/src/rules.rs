use diting_go_compat::text::{go_lower, go_trim_space};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Rule {
    pub allow: bool,
    pub pattern: String,
}

pub fn normalize(kind: &str, pattern: &str) -> Option<Rule> {
    let allow = match kind {
        "block" => false,
        "allow" => true,
        _ => return None,
    };
    let pattern = go_lower(go_trim_space(pattern)).into_owned();
    if !pattern.starts_with("http://") && !pattern.starts_with("https://") {
        return None;
    }
    Some(Rule { allow, pattern })
}

pub fn normalize_all(rules: &[(String, String)]) -> Vec<Rule> {
    rules
        .iter()
        .filter_map(|(kind, pattern)| normalize(kind, pattern))
        .collect()
}

#[cfg(test)]
mod tests;
