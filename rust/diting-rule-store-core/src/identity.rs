use std::net::IpAddr;

use serde_json::{json, Value};

use crate::probe::text;

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub enum TargetType {
    Ipv4,
    Ipv6,
    Cname,
}

impl TargetType {
    pub fn as_str(self) -> &'static str {
        match self {
            TargetType::Ipv4 => "IPv4",
            TargetType::Ipv6 => "IPv6",
            TargetType::Cname => "CNAME",
        }
    }
}

pub fn rewrite_target_type(target: Option<&str>) -> TargetType {
    match target {
        None | Some("") => TargetType::Cname,
        Some(text) => match text.parse::<IpAddr>() {
            Ok(IpAddr::V4(_)) => TargetType::Ipv4,
            Ok(IpAddr::V6(_)) => TargetType::Ipv6,
            Err(_) => TargetType::Cname,
        },
    }
}

pub fn tables(kind: &str) -> (&'static str, &'static str) {
    match kind {
        "allow" => ("allow_rule", "allow_rule_source"),
        "rewrite" => ("rewrite_rule", "rewrite_rule_source"),
        _ => ("block_rule", "block_rule_source"),
    }
}

fn scope_clause(column: &str) -> String {
    format!("({column} = ? OR {column} LIKE ? OR {column} LIKE ? OR {column} LIKE ?)")
}

fn scope_args(package: &str) -> Vec<Value> {
    vec![
        json!(package),
        json!(format!("{package}|%")),
        json!(format!("%|{package}|%")),
        json!(format!("%|{package}")),
    ]
}

pub fn predicate(name: &str, package: &str) -> (String, Vec<Value>) {
    let scope = scope_clause("appScope");
    let mut scope_values = scope_args(package);
    match name {
        "loadForApp" => {
            let mut args = scope_values;
            args.push(json!("*"));
            (
                format!("{scope} AND appInverted = 0 AND pattern <> ?"),
                args,
            )
        }
        "fullBlock" => {
            let mut args = vec![json!("*")];
            args.append(&mut scope_values);
            (format!("pattern = ? AND appInverted = 0 AND {scope}"), args)
        }
        "fullBlockEnabled" => {
            let mut args = vec![json!("*")];
            args.append(&mut scope_values);
            (
                format!("pattern = ? AND appInverted = 0 AND enabled = 1 AND {scope}"),
                args,
            )
        }
        _ => (scope, scope_values),
    }
}

#[derive(Clone, PartialEq, Eq, Debug)]
pub enum Flavor {
    Global,
    Scoped,
    FullBlock,
}

pub fn parse_flavor(value: &str) -> Flavor {
    match value {
        "scoped" => Flavor::Scoped,
        "fullBlock" => Flavor::FullBlock,
        _ => Flavor::Global,
    }
}

pub struct Identity {
    pub table: &'static str,
    pub source_table: &'static str,
    pub target_type: TargetType,
    pub where_sql: String,
    pub args: Vec<Value>,
    pub row: serde_json::Map<String, Value>,
}

pub fn identity(
    kind: &str,
    flavor: Flavor,
    rule: &Value,
    package: Option<&str>,
    now: i64,
) -> Identity {
    let (table, source_table) = tables(kind);
    if kind == "rewrite" {
        let target = text(rule, "target");
        let target_type = rewrite_target_type(target.as_deref());
        return Identity {
            table,
            source_table,
            target_type,
            where_sql: String::from("pattern = ? AND targetType = ? AND targetValue = ?"),
            args: vec![
                text(rule, "pattern")
                    .map(Value::String)
                    .unwrap_or(Value::Null),
                json!(target_type.as_str()),
                target.map(Value::String).unwrap_or(Value::Null),
            ],
            row: rewrite_row(rule, target_type, now),
        };
    }

    let pattern = text(rule, "pattern").unwrap_or_default();
    let important = crate::probe::flag(rule, "important").unwrap_or(false);
    let app_scope = text(rule, "appScope");
    let app_inverted = crate::probe::flag(rule, "appInverted").unwrap_or(false);

    let mut where_parts = vec![String::from("pattern = ?"), String::from("important = ?")];
    let mut args = vec![json!(pattern), json!(i32::from(important))];
    if flavor == Flavor::FullBlock {
        let (where_sql, scope_values) = predicate("fullBlock", package.unwrap_or_default());
        return Identity {
            table,
            source_table,
            target_type: TargetType::Cname,
            where_sql,
            args: scope_values,
            row: domain_row(rule, &pattern, now, package, flavor),
        };
    } else if let Some(scope) = package {
        where_parts.push(String::from("appScope = ?"));
        args.push(json!(scope));
    } else {
        match app_scope.as_deref() {
            Some(scope) => {
                where_parts.push(String::from("appScope = ?"));
                args.push(json!(scope));
            }
            None => where_parts.push(String::from("appScope IS NULL")),
        }
    }

    if flavor == Flavor::Global {
        where_parts.push(String::from("appInverted = ?"));
        args.push(json!(i32::from(app_inverted)));
        match text(rule, "dnsType") {
            Some(dns_type) => {
                where_parts.push(String::from("dnsType = ?"));
                args.push(json!(dns_type));
            }
            None => where_parts.push(String::from("dnsType IS NULL")),
        }
        where_parts.push(String::from("isRegex = ?"));
        args.push(json!(i32::from(
            crate::probe::flag(rule, "isRegex").unwrap_or(false),
        )));
    } else if flavor != Flavor::FullBlock {
        where_parts.push(String::from("appInverted = 0"));
    }

    Identity {
        table,
        source_table,
        target_type: TargetType::Cname,
        where_sql: where_parts.join(" AND "),
        args,
        row: domain_row(rule, &pattern, now, package, flavor),
    }
}

fn rewrite_row(rule: &Value, target_type: TargetType, now: i64) -> serde_json::Map<String, Value> {
    let pattern = text(rule, "pattern").unwrap_or_default();
    let raw_line = text(rule, "rawLine").unwrap_or_else(|| pattern.clone());
    let mut row = serde_json::Map::new();
    row.insert(String::from("pattern"), json!(pattern));
    row.insert(String::from("targetType"), json!(target_type.as_str()));
    row.insert(
        String::from("targetValue"),
        text(rule, "target")
            .map(Value::String)
            .unwrap_or(Value::Null),
    );
    row.insert(String::from("rawLine"), json!(raw_line));
    row.insert(String::from("addedAt"), json!(now));
    row.insert(String::from("enabled"), json!(1));
    row
}

fn domain_row(
    rule: &Value,
    pattern: &str,
    now: i64,
    package: Option<&str>,
    flavor: Flavor,
) -> serde_json::Map<String, Value> {
    let raw_line = match (flavor, package) {
        (Flavor::FullBlock, scope) => format!("*$app={}", scope.unwrap_or_default()),
        (Flavor::Scoped, _) => pattern.to_string(),
        _ => text(rule, "rawLine").unwrap_or_else(|| pattern.to_string()),
    };
    let mut row = serde_json::Map::new();
    row.insert(String::from("pattern"), json!(pattern));
    row.insert(String::from("rawLine"), json!(raw_line));
    row.insert(String::from("addedAt"), json!(now));
    row.insert(String::from("enabled"), json!(1));
    row.insert(
        String::from("groupName"),
        text(rule, "group")
            .map(Value::String)
            .unwrap_or(Value::Null),
    );
    row.insert(
        String::from("important"),
        json!(i32::from(
            crate::probe::flag(rule, "important").unwrap_or(false)
        )),
    );
    row.insert(
        String::from("appScope"),
        match package {
            Some(scope) => json!(scope),
            None => text(rule, "appScope")
                .map(Value::String)
                .unwrap_or(Value::Null),
        },
    );
    row.insert(
        String::from("appInverted"),
        json!(i32::from(
            crate::probe::flag(rule, "appInverted").unwrap_or(false)
        )),
    );
    row.insert(
        String::from("isWildcard"),
        json!(i32::from(pattern.contains('*'))),
    );
    row.insert(
        String::from("denyallow"),
        text(rule, "denyallow")
            .map(Value::String)
            .unwrap_or(Value::Null),
    );
    row.insert(
        String::from("isRegex"),
        json!(i32::from(
            crate::probe::flag(rule, "isRegex").unwrap_or(false)
        )),
    );
    row.insert(
        String::from("dnsType"),
        text(rule, "dnsType")
            .map(Value::String)
            .unwrap_or(Value::Null),
    );
    row
}

#[cfg(test)]
#[path = "identity/tests.rs"]
mod tests;
