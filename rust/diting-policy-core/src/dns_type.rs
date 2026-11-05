//! The subset of `github.com/miekg/dns`'s `StringToType` the rule engine needs.
//!
//! `specialRule` parses `dnsType` modifiers (`"AAAA"`, `"~A|AAAA"`) by looking the token up in the
//! Go map, so the table has to match it entry for entry. Generated from `dns.StringToType`
//! (miekg/dns v1.1.62) and pinned by a Go parity test that re-dumps the map and compares.

/// `dns.StringToType`: record type mnemonic -> numeric type.
const STRING_TO_TYPE: &[(&str, u16)] = &[
    ("A", 1),
    ("AAAA", 28),
    ("AFSDB", 18),
    ("AMTRELAY", 260),
    ("ANY", 255),
    ("APL", 42),
    ("ATMA", 34),
    ("AVC", 258),
    ("AXFR", 252),
    ("CAA", 257),
    ("CDNSKEY", 60),
    ("CDS", 59),
    ("CERT", 37),
    ("CNAME", 5),
    ("CSYNC", 62),
    ("DHCID", 49),
    ("DLV", 32769),
    ("DNAME", 39),
    ("DNSKEY", 48),
    ("DS", 43),
    ("EID", 31),
    ("EUI48", 108),
    ("EUI64", 109),
    ("GID", 102),
    ("GPOS", 27),
    ("HINFO", 13),
    ("HIP", 55),
    ("HTTPS", 65),
    ("IPSECKEY", 45),
    ("ISDN", 20),
    ("IXFR", 251),
    ("KEY", 25),
    ("KX", 36),
    ("L32", 105),
    ("L64", 106),
    ("LOC", 29),
    ("LP", 107),
    ("MAILA", 254),
    ("MAILB", 253),
    ("MB", 7),
    ("MD", 3),
    ("MF", 4),
    ("MG", 8),
    ("MINFO", 14),
    ("MR", 9),
    ("MX", 15),
    ("NAPTR", 35),
    ("NID", 104),
    ("NIMLOC", 32),
    ("NINFO", 56),
    ("NS", 2),
    ("NSAP-PTR", 23),
    ("NSEC", 47),
    ("NSEC3", 50),
    ("NSEC3PARAM", 51),
    ("NULL", 10),
    ("NXNAME", 128),
    ("NXT", 30),
    ("None", 0),
    ("OPENPGPKEY", 61),
    ("OPT", 41),
    ("PTR", 12),
    ("PX", 26),
    ("RKEY", 57),
    ("RP", 17),
    ("RRSIG", 46),
    ("RT", 21),
    ("Reserved", 65535),
    ("SIG", 24),
    ("SMIMEA", 53),
    ("SOA", 6),
    ("SPF", 99),
    ("SRV", 33),
    ("SSHFP", 44),
    ("SVCB", 64),
    ("TA", 32768),
    ("TALINK", 58),
    ("TKEY", 249),
    ("TLSA", 52),
    ("TSIG", 250),
    ("TXT", 16),
    ("UID", 101),
    ("UINFO", 100),
    ("UNSPEC", 103),
    ("URI", 256),
    ("X25", 19),
    ("ZONEMD", 63),
];

/// `dns.StringToType[token]`, case-sensitive like the Go map lookup (callers uppercase first).
pub fn string_to_type(token: &str) -> Option<u16> {
    STRING_TO_TYPE
        .iter()
        .find(|(name, _)| *name == token)
        .map(|(_, value)| *value)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn looks_up_the_types_rules_actually_use() {
        assert_eq!(string_to_type("A"), Some(1));
        assert_eq!(string_to_type("AAAA"), Some(28));
        assert_eq!(string_to_type("HTTPS"), Some(65));
        assert_eq!(string_to_type("a"), None);
        assert_eq!(string_to_type("NOPE"), None);
    }

    #[test]
    fn table_has_no_duplicate_mnemonics() {
        let mut names: Vec<&str> = STRING_TO_TYPE.iter().map(|(name, _)| *name).collect();
        names.sort_unstable();
        let before = names.len();
        names.dedup();
        assert_eq!(names.len(), before);
        assert_eq!(before, 87);
    }
}
