use std::net::{Ipv4Addr, Ipv6Addr};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Range {
    pub start: u128,
    pub end: u128,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Block {
    pub bits: u8,
    pub start: u128,
    pub prefix: u8,
}

fn family_max(bits: u8) -> u128 {
    if bits == 32 {
        u32::MAX as u128
    } else {
        u128::MAX
    }
}

fn range_for(bits: u8, value: u128, prefix: u8) -> Option<Range> {
    if prefix > bits {
        return None;
    }
    let host_bits = (bits - prefix) as u32;
    if host_bits == bits as u32 {
        return Some(Range {
            start: 0,
            end: family_max(bits),
        });
    }
    let size = 1u128 << host_bits;
    let start = value & (!0u128 << host_bits);
    Some(Range {
        start,
        end: start + (size - 1),
    })
}

pub(crate) fn parse_cidr(text: &str) -> Option<(u8, Range)> {
    let text = text.trim();
    let (address, prefix) = text.split_once('/')?;
    if prefix.is_empty()
        || !prefix.bytes().all(|byte| byte.is_ascii_digit())
        || (prefix.len() > 1 && prefix.starts_with('0'))
    {
        return None;
    }
    let prefix = prefix.parse::<u8>().ok()?;
    if let Ok(v4) = address.parse::<Ipv4Addr>() {
        return range_for(32, u32::from(v4) as u128, prefix).map(|range| (32, range));
    }
    let v6 = address.parse::<Ipv6Addr>().ok()?;
    range_for(128, u128::from(v6), prefix).map(|range| (128, range))
}

fn merge_ranges(mut ranges: Vec<Range>) -> Vec<Range> {
    ranges.sort_by_key(|range| (range.start, range.end));
    let mut merged: Vec<Range> = Vec::with_capacity(ranges.len());
    for range in ranges {
        if let Some(last) = merged.last_mut() {
            if range.start <= last.end.saturating_add(1) {
                if range.end > last.end {
                    last.end = range.end;
                }
                continue;
            }
        }
        merged.push(range);
    }
    merged
}

fn subtract_ranges(included: &[Range], excluded: &[Range]) -> Vec<Range> {
    let mut remaining = Vec::new();
    for include in included {
        let mut cursor = include.start;
        let mut consumed = false;
        for exclude in excluded {
            if exclude.end < cursor || exclude.start > include.end {
                continue;
            }
            if exclude.start > cursor {
                remaining.push(Range {
                    start: cursor,
                    end: exclude.start - 1,
                });
            }
            if exclude.end >= include.end {
                consumed = true;
                break;
            }
            cursor = exclude.end + 1;
        }
        if !consumed && cursor <= include.end {
            remaining.push(Range {
                start: cursor,
                end: include.end,
            });
        }
    }
    remaining
}

fn range_to_blocks(bits: u8, range: Range, out: &mut Vec<Block>) {
    let mut start = range.start;
    loop {
        let mut emitted = false;
        for prefix in 0..=bits {
            let host_bits = (bits - prefix) as u32;
            if host_bits == 128 {
                if start == 0 && range.end == u128::MAX {
                    out.push(Block {
                        bits,
                        start,
                        prefix,
                    });
                    return;
                }
                continue;
            }
            let size = 1u128 << host_bits;
            if !start.is_multiple_of(size) || size - 1 > range.end - start {
                continue;
            }
            out.push(Block {
                bits,
                start,
                prefix,
            });
            if size - 1 == range.end - start {
                return;
            }
            start += size;
            emitted = true;
            break;
        }
        if !emitted {
            return;
        }
    }
}

fn collect(addresses: &[String]) -> (Vec<Range>, Vec<Range>) {
    let mut v4 = Vec::new();
    let mut v6 = Vec::new();
    for text in addresses {
        if let Some((bits, range)) = parse_cidr(text) {
            if bits == 32 {
                v4.push(range);
            } else {
                v6.push(range);
            }
        }
    }
    (v4, v6)
}

pub(crate) fn subtract_cidrs(
    include: &[String],
    exclude: &[String],
    whole_when_empty: bool,
) -> Vec<Block> {
    let (include_v4, include_v6) = collect(include);
    let (exclude_v4, exclude_v6) = collect(exclude);
    let mut blocks = Vec::new();
    for (bits, include, exclude) in [
        (32u8, include_v4, exclude_v4),
        (128u8, include_v6, exclude_v6),
    ] {
        let included = if include.is_empty() && whole_when_empty {
            vec![Range {
                start: 0,
                end: family_max(bits),
            }]
        } else {
            merge_ranges(include)
        };
        let excluded = merge_ranges(exclude);
        for range in subtract_ranges(&included, &excluded) {
            range_to_blocks(bits, range, &mut blocks);
        }
    }
    blocks
}

fn covers(block: &Block, value: u128) -> bool {
    if block.prefix == 0 {
        return true;
    }
    let host_bits = (block.bits - block.prefix) as u32;
    let size = 1u128 << host_bits;
    value >= block.start && value - block.start < size
}

pub(crate) fn force_host(blocks: &mut Vec<Block>, bits: u8, value: u128) {
    if blocks
        .iter()
        .any(|block| block.bits == bits && covers(block, value))
    {
        return;
    }
    blocks.push(Block {
        bits,
        start: value,
        prefix: bits,
    });
}

pub(crate) fn format_address(block: &Block) -> String {
    if block.bits == 32 {
        Ipv4Addr::from(block.start as u32).to_string()
    } else {
        Ipv6Addr::from(block.start).to_string()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn strings(items: &[&str]) -> Vec<String> {
        items.iter().map(|item| (*item).to_owned()).collect()
    }

    fn cidrs(items: &[&str]) -> Vec<String> {
        let blocks = subtract_cidrs(&strings(items), &[], true);
        blocks
            .iter()
            .map(|block| format!("{}/{}", format_address(block), block.prefix))
            .collect()
    }

    #[test]
    fn invalid_entries_are_ignored() {
        assert!(parse_cidr("10.0.0.0").is_none());
        assert!(parse_cidr("10.0.0.0/33").is_none());
        assert!(parse_cidr("10.0.0.0/08").is_none());
        assert!(parse_cidr("nonsense").is_none());
        assert!(parse_cidr("2001:db8::/129").is_none());
        assert!(parse_cidr("2001:db8::%eth0/64").is_none());
        assert_eq!(
            cidrs(&["nonsense", "10.0.0.0/8"]),
            vec!["10.0.0.0/8", "::/0"]
        );
    }

    #[test]
    fn subtraction_emits_the_fewest_blocks() {
        let blocks = subtract_cidrs(
            &strings(&["10.0.0.0/8"]),
            &strings(&["10.128.0.0/9"]),
            false,
        );
        let rendered: Vec<String> = blocks
            .iter()
            .map(|block| format!("{}/{}", format_address(block), block.prefix))
            .collect();
        assert_eq!(rendered, vec!["10.0.0.0/9"]);
    }

    #[test]
    fn whole_when_empty_covers_both_families() {
        assert_eq!(cidrs(&[]), vec!["0.0.0.0/0", "::/0"]);
    }

    #[test]
    fn excluding_a_whole_family_empties_it() {
        let blocks = subtract_cidrs(&strings(&["10.0.0.0/8"]), &strings(&["10.0.0.0/8"]), false);
        assert!(blocks.is_empty());
    }

    #[test]
    fn force_host_is_idempotent_when_covered() {
        let mut blocks = subtract_cidrs(&strings(&[]), &[], true);
        let before = blocks.len();
        force_host(
            &mut blocks,
            32,
            u32::from(Ipv4Addr::new(10, 0, 0, 1)) as u128,
        );
        assert_eq!(blocks.len(), before);

        let mut narrowed =
            subtract_cidrs(&strings(&["10.0.0.0/8"]), &strings(&["10.0.0.0/9"]), false);
        force_host(
            &mut narrowed,
            32,
            u32::from(Ipv4Addr::new(10, 0, 0, 1)) as u128,
        );
        assert!(narrowed.iter().any(|block| {
            block.bits == 32
                && block.prefix == 32
                && block.start == u32::from(Ipv4Addr::new(10, 0, 0, 1)) as u128
        }));
    }

    #[test]
    fn ipv6_whole_space_is_one_block() {
        let blocks = subtract_cidrs(&strings(&["::/0"]), &[], false);
        assert_eq!(blocks.len(), 1);
        assert_eq!(blocks[0].bits, 128);
        assert_eq!(blocks[0].prefix, 0);
    }
}
