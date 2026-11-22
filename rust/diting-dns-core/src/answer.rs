use std::collections::HashSet;

use diting_go_compat::ip;

pub const TYPE_A: u8 = 1;
pub const TYPE_AAAA: u8 = 28;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct AnswerEntry<'a> {
    pub rrtype: u8,
    pub address: &'a [u8],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Inspection {
    pub blocked: bool,
    pub addresses: String,
}

pub fn inspect(entries: &[AnswerEntry<'_>]) -> Inspection {
    let mut ip_records = 0u32;
    let mut null_records = 0u32;
    let mut addresses: Vec<String> = Vec::with_capacity(entries.len());
    let mut seen: HashSet<String> = HashSet::with_capacity(entries.len());

    for entry in entries {
        let null = match entry.rrtype {
            TYPE_A => {
                ip_records += 1;
                ip::equals_ipv4_zero(entry.address) || ip::is_loopback(entry.address)
            }
            TYPE_AAAA => {
                ip_records += 1;
                ip::equals_ipv6_zero(entry.address) || ip::is_loopback(entry.address)
            }
            _ => continue,
        };
        if null {
            null_records += 1;
        }
        let text = ip::go_ip_string(entry.address);
        if seen.insert(text.clone()) {
            addresses.push(text);
        }
    }

    Inspection {
        blocked: ip_records > 0 && null_records == ip_records,
        addresses: addresses.join(","),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry<'a>(rrtype: u8, address: &'a [u8]) -> AnswerEntry<'a> {
        AnswerEntry { rrtype, address }
    }

    #[test]
    fn empty_and_non_address_answers_are_not_blocks() {
        assert_eq!(
            inspect(&[]),
            Inspection {
                blocked: false,
                addresses: String::new()
            }
        );
        let cname = [0u8; 16];
        assert!(!inspect(&[entry(5, &cname)]).blocked);
    }

    #[test]
    fn dedupe_keeps_answer_order_and_mapped_forms_collapse() {
        let mut mapped = [0u8; 16];
        mapped[10] = 0xff;
        mapped[11] = 0xff;
        mapped[12..].copy_from_slice(&[1, 2, 3, 4]);
        let inspection = inspect(&[
            entry(TYPE_A, &mapped),
            entry(TYPE_AAAA, &[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]),
            entry(TYPE_A, &[1, 2, 3, 4]),
        ]);
        assert_eq!(inspection.addresses, "1.2.3.4,::1");
        assert!(!inspection.blocked, "a public address is not a null block");
    }
}
