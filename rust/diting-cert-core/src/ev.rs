use std::sync::OnceLock;

pub const EV_POLICY_OIDS: [&str; 8] = [
    "2.23.140.1.1",
    "1.3.6.1.4.1.6449.1.2.1.5.1",
    "2.16.840.1.114412.2.1",
    "2.16.840.1.114404.1.1.2.4.1",
    "1.3.6.1.4.1.14370.1.6",
    "2.16.840.1.113733.1.7.23.6",
    "1.3.6.1.4.1.4146.1.1",
    "1.3.6.1.4.1.34697.2.1",
];

pub fn is_extended_validation(policy_identifiers: &[&str]) -> bool {
    let table = table();
    for candidate in policy_identifiers {
        let Some(arcs) = parse_oid(candidate) else {
            continue;
        };
        if table.contains(&arcs) {
            return true;
        }
    }
    false
}

pub fn is_extended_validation_csv(csv: &str) -> bool {
    let entries: Vec<&str> = csv.split(',').filter(|entry| !entry.is_empty()).collect();
    is_extended_validation(&entries)
}

fn table() -> &'static [Vec<u64>] {
    static TABLE: OnceLock<Vec<Vec<u64>>> = OnceLock::new();
    TABLE.get_or_init(|| {
        EV_POLICY_OIDS
            .iter()
            .filter_map(|oid| parse_oid(oid))
            .collect()
    })
}

fn parse_oid(text: &str) -> Option<Vec<u64>> {
    if text.is_empty() {
        return None;
    }
    let mut arcs = Vec::with_capacity(8);
    for part in text.split('.') {
        if part.is_empty() || !part.bytes().all(|byte| byte.is_ascii_digit()) {
            return None;
        }
        arcs.push(part.parse::<u64>().ok()?);
    }
    if arcs.len() < 2 {
        return None;
    }
    Some(arcs)
}

#[cfg(test)]
mod tests;
