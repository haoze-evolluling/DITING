//! The extended-validation policy OID table behind "do not inspect this certificate".
//!
//! `mitm_relay.go` looks at the upstream leaf's `PolicyIdentifiers` and, on a hit, leaves HTTPS to
//! the real server (banking and identity endpoints commonly pin or expect EV treatment). The table
//! is the old `evPolicyOIDs` list; the comparison is Go's `asn1.ObjectIdentifier.Equal`, i.e. arc
//! by arc over the numeric values, so a caller may pass the dotted text in any spelling that is
//! numerically equal.
//!
//! The caller hands the OIDs over as one comma separated string (`oid.String()` joined by `,`),
//! which is how they leave Go. An entry that is not a dotted-decimal OID simply does not match; it
//! can never make a certificate look like EV by accident.

use std::sync::OnceLock;

/// `evPolicyOIDs` from the old `mitm_trust.go`, in the same order.
pub const EV_POLICY_OIDS: [&str; 8] = [
    "2.23.140.1.1",                // CA/Browser Forum EV
    "1.3.6.1.4.1.6449.1.2.1.5.1",  // Comodo / Sectigo
    "2.16.840.1.114412.2.1",       // DigiCert
    "2.16.840.1.114404.1.1.2.4.1", // Symantec / GeoTrust
    "1.3.6.1.4.1.14370.1.6",       // GlobalSign
    "2.16.840.1.113733.1.7.23.6",  // Thawte
    "1.3.6.1.4.1.4146.1.1",        // VeriSign
    "1.3.6.1.4.1.34697.2.1",       // AffirmTrust
];

/// `isExtendedValidation` over a certificate's policy identifiers.
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

/// [`is_extended_validation`] over the comma separated form the Go side sends.
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

/// The numeric arcs of a dotted-decimal OID, or `None` when it is not one.
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
