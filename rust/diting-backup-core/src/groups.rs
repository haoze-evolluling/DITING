//! The fifteen backup groups and the order they are written in.
//!
//! Keys are a file format: never rename, never reorder (the `selection` array is written in
//! declaration order so two equal backups are byte-identical).

use serde_json::json;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum Group {
    Providers,
    Bootstrap,
    Cache,
    Outbound,
    Subscriptions,
    DomainRules,
    RewriteDomain,
    RewriteCname,
    AddressRules,
    Excluded,
    Blocked,
    Allowlist,
    HttpInspection,
    Appearance,
    System,
}

/// Declaration order; also the write order of `data` and `selection`.
pub const ORDER: [Group; 15] = [
    Group::Providers,
    Group::Bootstrap,
    Group::Cache,
    Group::Outbound,
    Group::Subscriptions,
    Group::DomainRules,
    Group::RewriteDomain,
    Group::RewriteCname,
    Group::AddressRules,
    Group::Excluded,
    Group::Blocked,
    Group::Allowlist,
    Group::HttpInspection,
    Group::Appearance,
    Group::System,
];

impl Group {
    pub fn key(self) -> &'static str {
        match self {
            Group::Providers => "providers",
            Group::Bootstrap => "bootstrap",
            Group::Cache => "cache",
            Group::Outbound => "outbound",
            Group::Subscriptions => "subscriptions",
            Group::DomainRules => "domainRules",
            Group::RewriteDomain => "rewriteDomain",
            Group::RewriteCname => "rewriteCname",
            Group::AddressRules => "addressRules",
            Group::Excluded => "excluded",
            Group::Blocked => "blocked",
            Group::Allowlist => "allowlist",
            Group::HttpInspection => "httpInspection",
            Group::Appearance => "appearance",
            Group::System => "system",
        }
    }

    pub fn from_key(key: &str) -> Option<Group> {
        ORDER.into_iter().find(|group| group.key() == key)
    }

    /// Groups that need the rule database; a missing database is an error, never a silent skip.
    pub fn needs_database(self) -> bool {
        matches!(
            self,
            Group::Subscriptions
                | Group::DomainRules
                | Group::RewriteDomain
                | Group::RewriteCname
                | Group::AddressRules
        )
    }

    pub fn is_rewrite(self) -> bool {
        matches!(self, Group::RewriteDomain | Group::RewriteCname)
    }

    /// `targetType` values this group owns; the two rewrite groups split one table.
    pub fn target_types(self) -> &'static [&'static str] {
        match self {
            Group::RewriteDomain => &["IPv4", "IPv6"],
            Group::RewriteCname => &["CNAME"],
            _ => &[],
        }
    }
}

/// Selection array in declaration order, unknown keys dropped.
pub fn ordered_keys(requested: &[String]) -> Vec<Group> {
    let mut wanted = Vec::new();
    for key in requested {
        if let Some(group) = Group::from_key(key) {
            if !wanted.contains(&group) {
                wanted.push(group);
            }
        }
    }
    ORDER
        .into_iter()
        .filter(|group| wanted.contains(group))
        .collect()
}

pub fn skip_entry(group: Group, reason: &str) -> serde_json::Value {
    json!({"group": group.key(), "reason": reason})
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_round_trip_in_declaration_order() {
        assert_eq!(ORDER.len(), 15);
        for group in ORDER {
            assert_eq!(Group::from_key(group.key()), Some(group));
        }
        assert_eq!(Group::from_key("nope"), None);
        let requested = vec![
            String::from("system"),
            String::from("providers"),
            String::from("system"),
            String::from("bogus"),
        ];
        let ordered = ordered_keys(&requested);
        assert_eq!(ordered, vec![Group::Providers, Group::System]);
    }

    #[test]
    fn rewrite_groups_split_by_target_type() {
        assert_eq!(Group::RewriteDomain.target_types(), &["IPv4", "IPv6"]);
        assert_eq!(Group::RewriteCname.target_types(), &["CNAME"]);
        assert!(Group::Subscriptions.needs_database());
        assert!(!Group::Appearance.needs_database());
    }
}
