//! DTRI writer: the mmap-able subscription-rule index the Go tunnel engine reads.
//!
//! A byte-for-byte port of `MappedSubscriptionRuleIndex.compile` in
//! `android/app/android/app/src/main/kotlin/com/haoze/diting/core/rule/`; the Kotlin
//! implementation stays in place and is the reference the fixtures are checked against.
//!
//! Only plain rules belong in a trie. Wildcards, regexes, app-scoped / inverted rules and rules
//! carrying `denyallow` or `dnstype` are skipped exactly like the Kotlin filter does, and the
//! caller (`BlockRuleLoader`/`AllowRuleLoader`) already narrows the feed per file.
//!
//! File layout (all integers big-endian, identical to the Kotlin writer):
//!
//! ```text
//! magic "DTRI" | version | nodes | edges | sources | bloomBits | bloomBytes |
//! labelsBytes | sourcesBytes
//! bloom | nodes * (source, firstEdge, edgeCount) | edges * (labelOffset, labelLength, child) |
//! labels | sources * (length, UTF-8 bytes)
//! ```
//!
//! Labels and patterns live in two shared byte pools instead of one `String` per trie node: a
//! 100k-rule compile is mostly allocation-bound, and this keeps it to a handful of growing buffers.
//!
//! Known parity note: the bloom filter hashes UTF-16 code units (`& 0xff`), because that is what
//! the Kotlin writer does. Plain patterns are ASCII after rule normalization, so this only matters
//! for the Unicode fixtures we keep to pin the byte format.

use std::borrow::Cow;
use std::cmp::Ordering;
use std::collections::HashMap;

pub const MAGIC: u32 = 0x4454_5249;
pub const VERSION: u32 = 1;
const HEADER_INTS: usize = 9;
const NODE_SIZE: usize = 12;
const EDGE_SIZE: usize = 12;
const BLOOM_HASHES: usize = 7;

/// One rule as the Kotlin compiler sees it. `important` is not part of the trie (the caller feeds
/// the normal and important files separately), so it is not modelled here.
#[derive(Debug, Clone)]
pub struct Rule<'a> {
    pub pattern: &'a str,
    pub source: &'a str,
    pub app_scope: Option<&'a str>,
    pub app_inverted: bool,
    pub is_wildcard: bool,
    pub denyallow: Option<&'a str>,
    pub is_regex: bool,
    pub dns_type: Option<&'a str>,
}

/// `!isNullOrEmpty()` in Kotlin: null and the empty string both mean "not set".
fn is_set(value: Option<&str>) -> bool {
    matches!(value, Some(text) if !text.is_empty())
}

/// The Kotlin `compile` filter: these rules never enter a trie.
fn is_skipped(rule: &Rule<'_>) -> bool {
    rule.is_wildcard
        || rule.pattern.contains('*')
        || is_set(rule.app_scope)
        || rule.app_inverted
        || rule.is_regex
        || is_set(rule.denyallow)
        || is_set(rule.dns_type)
}

/// Compiles `rules` into a DTRI image. An empty input still produces a valid root-only file, which
/// is what the Kotlin compiler does for an empty page set.
pub fn compile(rules: &[Rule<'_>]) -> Vec<u8> {
    let mut nodes: Vec<Node<'_>> = vec![Node::default()];
    let mut labels: String = String::new();
    let mut label_spans: HashMap<Box<str>, (u32, u32)> = HashMap::new();
    // (parent node, label start, label length) -> child node. A trie node keyed by an interned
    // label keeps the build O(labels) instead of scanning a fan-out of hundreds of children.
    let mut edges: HashMap<(u32, u32, u32), u32> = HashMap::new();
    let mut patterns: String = String::new();
    let mut sources: Vec<&str> = Vec::new();
    let mut rule_count = 0usize;

    for rule in rules {
        if is_skipped(rule) {
            continue;
        }
        let lowered = lowercase(rule.pattern);
        let pattern = lowered.trim_end_matches('.');
        let pattern_start = patterns.len() as u32;
        patterns.push_str(pattern);
        let pattern_end = patterns.len() as u32;

        // Labels are stored from the TLD down: "ads.example.com" indexes com -> example -> ads.
        let mut node = 0usize;
        let mut end = pattern.len();
        while end > 0 {
            let dot = pattern[..end].rfind('.');
            let start = dot.map_or(0, |index| index + 1);
            let (label_start, label_length) =
                intern(&pattern[start..end], &mut labels, &mut label_spans);
            let key = (node as u32, label_start, label_length);
            node = match edges.get(&key) {
                Some(child) => *child as usize,
                None => {
                    let child = nodes.len() as u32;
                    nodes.push(Node::default());
                    edges.insert(key, child);
                    nodes[node].children.push(LabelRef {
                        start: label_start,
                        length: label_length,
                        child,
                    });
                    child as usize
                }
            };
            end = dot.unwrap_or(0);
        }
        let keep_existing = matches!(
            nodes[node].source,
            Some(existing) if utf16_cmp(rule.source, existing) != Ordering::Less
        );
        if !keep_existing {
            nodes[node].source = Some(rule.source);
        }
        nodes[node].pattern = Some((pattern_start, pattern_end));
        sources.push(rule.source);
        rule_count += 1;
    }

    let mut source_names = sources;
    source_names.sort_by(|left, right| utf16_cmp(left, right));
    source_names.dedup();
    let source_ids: HashMap<&str, u32> = source_names
        .iter()
        .enumerate()
        .map(|(index, name)| (*name, index as u32))
        .collect();

    // Pre-order node numbering, children sorted by the same UTF-16 order the Kotlin writer uses.
    let mut order = Vec::with_capacity(nodes.len());
    let mut node_index = vec![usize::MAX; nodes.len()];
    assign(0, &nodes, &labels, &mut order, &mut node_index);

    let mut out_labels: Vec<u8> = Vec::with_capacity(labels.len());
    let mut flat_edges: Vec<(u32, u32, u32)> = Vec::new();
    let mut flat_nodes: Vec<(i32, u32, u32)> = Vec::with_capacity(nodes.len());
    for &node in &order {
        let first_edge = flat_edges.len() as u32;
        for child in sorted_children(&nodes[node], &labels) {
            let offset = out_labels.len() as u32;
            let label = child.label(&labels);
            out_labels.extend_from_slice(label.as_bytes());
            flat_edges.push((
                offset,
                label.len() as u32,
                node_index[child.child as usize] as u32,
            ));
        }
        let source = nodes[node]
            .source
            .map_or(-1, |name| source_ids[name] as i32);
        flat_nodes.push((source, first_edge, flat_edges.len() as u32 - first_edge));
    }

    let bloom_bits = (rule_count * 10).max(64);
    let bloom_bytes = bloom_bits.div_ceil(8);
    let mut bloom = vec![0u8; bloom_bytes];
    for &node in &order {
        if let Some((start, end)) = nodes[node].pattern {
            add_bloom(
                &mut bloom,
                bloom_bits,
                &patterns[start as usize..end as usize],
            );
        }
    }

    let source_bytes: usize = source_names.iter().map(|name| 4 + name.len()).sum();
    let mut out = Vec::with_capacity(
        HEADER_INTS * 4
            + bloom.len()
            + flat_nodes.len() * NODE_SIZE
            + flat_edges.len() * EDGE_SIZE
            + out_labels.len()
            + source_bytes,
    );
    for value in [
        MAGIC,
        VERSION,
        flat_nodes.len() as u32,
        flat_edges.len() as u32,
        source_names.len() as u32,
        bloom_bits as u32,
        bloom_bytes as u32,
        out_labels.len() as u32,
        source_bytes as u32,
    ] {
        out.extend_from_slice(&value.to_be_bytes());
    }
    out.extend_from_slice(&bloom);
    for (source, first_edge, edge_count) in flat_nodes {
        out.extend_from_slice(&source.to_be_bytes());
        out.extend_from_slice(&first_edge.to_be_bytes());
        out.extend_from_slice(&edge_count.to_be_bytes());
    }
    for (label_offset, label_length, child) in flat_edges {
        out.extend_from_slice(&label_offset.to_be_bytes());
        out.extend_from_slice(&label_length.to_be_bytes());
        out.extend_from_slice(&child.to_be_bytes());
    }
    out.extend_from_slice(&out_labels);
    for name in &source_names {
        out.extend_from_slice(&(name.len() as u32).to_be_bytes());
        out.extend_from_slice(name.as_bytes());
    }
    out
}

/// Returns the `(start, length)` span of `label` in the shared pool, appending it on first use.
fn intern(
    label: &str,
    labels: &mut String,
    spans: &mut HashMap<Box<str>, (u32, u32)>,
) -> (u32, u32) {
    if let Some(span) = spans.get(label) {
        return *span;
    }
    let start = labels.len() as u32;
    labels.push_str(label);
    let span = (start, label.len() as u32);
    spans.insert(Box::from(label), span);
    span
}

/// Compiles the packed payload the Kotlin side sends over JNI. `None` means the payload is
/// malformed (or absurdly large) and the caller should fall back to the Kotlin compiler.
///
/// ```text
/// u32 count | count * (u32 patternLen, pattern, u32 sourceLen, source, u8 flags,
///                      u32 appScopeLen | u32::MAX, appScope,
///                      u32 denyallowLen | u32::MAX, denyallow,
///                      u32 dnsTypeLen | u32::MAX, dnsType)
/// flags: bit 0 wildcard, bit 1 appInverted, bit 2 regex
/// ```
pub fn compile_packed(payload: &[u8]) -> Option<Vec<u8>> {
    let mut reader = Reader::new(payload);
    let count = reader.u32()? as usize;
    // Every record needs at least the two length prefixes and the flags byte.
    if count > payload.len() {
        return None;
    }
    let mut owned = Vec::with_capacity(count);
    for _ in 0..count {
        let pattern = reader.string()?.to_string();
        let source = reader.string()?.to_string();
        let flags = reader.u8()?;
        let app_scope = reader.optional_string()?.map(str::to_string);
        let denyallow = reader.optional_string()?.map(str::to_string);
        let dns_type = reader.optional_string()?.map(str::to_string);
        owned.push(OwnedRule {
            pattern,
            source,
            flags,
            app_scope,
            denyallow,
            dns_type,
        });
    }
    if !reader.is_empty() {
        return None;
    }
    let rules: Vec<Rule<'_>> = owned
        .iter()
        .map(|rule| Rule {
            pattern: &rule.pattern,
            source: &rule.source,
            app_scope: rule.app_scope.as_deref(),
            app_inverted: rule.flags & 0b10 != 0,
            is_wildcard: rule.flags & 0b1 != 0,
            denyallow: rule.denyallow.as_deref(),
            is_regex: rule.flags & 0b100 != 0,
            dns_type: rule.dns_type.as_deref(),
        })
        .collect();
    Some(compile(&rules))
}

#[derive(Default)]
struct Node<'a> {
    children: Vec<LabelRef>,
    source: Option<&'a str>,
    /// Range in the shared pattern pool, used for the bloom filter.
    pattern: Option<(u32, u32)>,
}

/// One `(label, child)` edge; the label lives in the shared label pool.
#[derive(Clone, Copy)]
struct LabelRef {
    start: u32,
    length: u32,
    child: u32,
}

impl LabelRef {
    fn label<'a>(&self, labels: &'a str) -> &'a str {
        &labels[self.start as usize..(self.start + self.length) as usize]
    }
}

struct OwnedRule {
    pattern: String,
    source: String,
    flags: u8,
    app_scope: Option<String>,
    denyallow: Option<String>,
    dns_type: Option<String>,
}

fn sorted_children<'a>(node: &Node<'a>, labels: &str) -> Vec<LabelRef> {
    let mut children = node.children.clone();
    children.sort_by(|left, right| utf16_cmp(left.label(labels), right.label(labels)));
    children
}

fn assign(
    nodes_index: usize,
    nodes: &[Node<'_>],
    labels: &str,
    order: &mut Vec<usize>,
    node_index: &mut [usize],
) {
    node_index[nodes_index] = order.len();
    order.push(nodes_index);
    for child in sorted_children(&nodes[nodes_index], labels) {
        assign(child.child as usize, nodes, labels, order, node_index);
    }
}

/// Kotlin `String.lowercase()` (invariant locale). ASCII input is the common case and skipping the
/// allocation for it keeps the compile cheap without changing a single output byte.
fn lowercase(pattern: &str) -> Cow<'_, str> {
    if !pattern.is_ascii() {
        return Cow::Owned(pattern.to_lowercase());
    }
    if pattern.bytes().any(|byte| byte.is_ascii_uppercase()) {
        Cow::Owned(pattern.to_ascii_lowercase())
    } else {
        Cow::Borrowed(pattern)
    }
}

/// Kotlin's `String.compareTo` compares UTF-16 code units; sorting by UTF-8 bytes would order
/// astral-plane labels differently.
fn utf16_cmp(left: &str, right: &str) -> Ordering {
    left.encode_utf16().cmp(right.encode_utf16())
}

fn add_bloom(bloom: &mut [u8], bits: usize, value: &str) {
    let (h1, h2) = hashes(value);
    for index in 0..BLOOM_HASHES {
        let sum = h1.wrapping_add((index as i64).wrapping_mul(h2));
        let bit = sum.rem_euclid(bits as i64) as usize;
        bloom[bit / 8] |= 1 << (bit % 8);
    }
}

/// Kotlin `hashes`: FNV-1a offsets, folding each UTF-16 code unit through its low byte.
fn hashes(value: &str) -> (i64, i64) {
    let mut h1: i64 = -3750763034362895579;
    let mut h2: i64 = h1;
    for unit in value.encode_utf16() {
        let byte = i64::from(unit & 0xff);
        h1 = (h1 ^ byte).wrapping_mul(1_099_511_628_211);
        h2 = h2.wrapping_mul(1_099_511_628_211) ^ byte;
    }
    (h1, h2 | 1)
}

struct Reader<'a> {
    bytes: &'a [u8],
    offset: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, offset: 0 }
    }

    fn is_empty(&self) -> bool {
        self.offset >= self.bytes.len()
    }

    fn take(&mut self, length: usize) -> Option<&'a [u8]> {
        let end = self.offset.checked_add(length)?;
        let slice = self.bytes.get(self.offset..end)?;
        self.offset = end;
        Some(slice)
    }

    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }

    fn u32(&mut self) -> Option<u32> {
        let bytes = self.take(4)?;
        Some(u32::from_be_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]))
    }

    fn string(&mut self) -> Option<&'a str> {
        let length = self.u32()? as usize;
        std::str::from_utf8(self.take(length)?).ok()
    }

    fn optional_string(&mut self) -> Option<Option<&'a str>> {
        let length = self.u32()?;
        if length == u32::MAX {
            return Some(None);
        }
        Some(Some(std::str::from_utf8(self.take(length as usize)?).ok()?))
    }
}

#[cfg(test)]
mod tests;
