//! The `applyRuleSnapshot` document builder behind `RuleSnapshotStore.kt`.
//!
//! This is the whole classification/export/JSON half of `android/app/.../core/rule/`:
//! `BlockRuleLoader` + `AllowRuleLoader` + `RuleSnapshotStore.buildJson`. Kotlin keeps the SQLite
//! reads (`RuleSnapshotDao`), the DTRI compile call and the stamp file's I/O; [`plan`] here holds
//! the decisions around them (which trie paths are usable, whether the stamp may be refreshed and
//! which rows must stay inline), and the JSON document is built by [`build`].
//!
//! Semantics are field-for-field with the Kotlin it replaces:
//!
//! * a row is "special" when `isRegex`, `denyallow` or `dnsType` is non-empty, and is then passed
//!   through verbatim (`isWildcard` becomes `isWildcard || pattern.contains('*')`);
//! * an app-inverted row with a non-empty `appScope` becomes an inverted rule with the trimmed,
//!   lowercased, de-duplicated package list;
//! * an app-scoped row lands in that package's bucket (exact or wildcard, normal or important);
//! * a plain subscription row is omitted when its trie holds it (the Go engine reads the DTRI
//!   file), and repeated inline as a fallback otherwise;
//! * the exported lists keep first-occurrence order (the Kotlin `LinkedHashSet`/`LinkedHashMap`
//!   shapes), and the JSON carries exactly the fields `RuleSnapshotStore` used to put.
//!
//! Map iteration order is the one place where this is not bit-identical to the Kotlin: the Kotlin
//! loaders kept exact rules in `HashMap`, whose iteration order is hash-based, so the *order* of
//! exact rules inside `globalBlock`/`appRules` was arbitrary. The Go policy kernel loads those into
//! maps (order cannot change a verdict), and this side emits DB/insertion order instead.
//!
//! Nothing here touches a database, a file or the clock, so the whole pipeline is replayable from
//! a row payload (see `tests/`).

use std::collections::{HashMap, HashSet};

use serde::Serialize;

pub(crate) mod payload;
pub mod plan;

/// One `EnabledRule` row as the DAO projects it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Row {
    pub pattern: String,
    pub source: String,
    pub important: bool,
    pub app_scope: Option<String>,
    pub app_inverted: bool,
    pub is_wildcard: bool,
    pub denyallow: Option<String>,
    pub is_regex: bool,
    pub dns_type: Option<String>,
}

/// The rows and index state of one dataset's block or allow half.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct LoadInput {
    pub index_usable: bool,
    pub important_usable: bool,
    pub custom: Vec<Row>,
    pub subscription: Vec<Row>,
}

/// Everything one `buildSnapshotJson` call needs.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SnapshotInput {
    pub filter_enabled: bool,
    /// `blockTriePath`, `importantBlockTriePath`, `allowTriePath`, `importantAllowTriePath`.
    pub trie_paths: [Option<String>; 4],
    pub app_allowlist: Vec<(String, Vec<String>)>,
    pub block: LoadInput,
    pub allow: LoadInput,
}

/// Builds the `applyRuleSnapshot` document.
pub fn build(input: &SnapshotInput) -> String {
    let block = load(&input.block).block_export();
    let allow = load(&input.allow).allow_export();
    let app_rules = app_rules_json(&block, &allow, &input.app_allowlist);
    let document = SnapshotJson {
        filter_enabled: input.filter_enabled,
        block_trie_path: input.trie_paths[0].as_deref(),
        important_block_trie_path: input.trie_paths[1].as_deref(),
        allow_trie_path: input.trie_paths[2].as_deref(),
        important_allow_trie_path: input.trie_paths[3].as_deref(),
        global_allow: allow.global_allow.clone(),
        global_block: block.global_block.clone(),
        global_important: block.global_important.clone(),
        app_rules,
        inverted_block: block
            .inverted
            .iter()
            .map(|rule| InvertedBlockJson {
                pattern: &rule.pattern,
                source: &rule.source,
                important: rule.important,
                excluded_apps: &rule.excluded,
            })
            .collect(),
        inverted_allow: allow
            .inverted
            .iter()
            .map(|rule| InvertedAllowJson {
                pattern: &rule.pattern,
                excluded_apps: &rule.excluded,
            })
            .collect(),
        disabled_rules: Vec::new(),
        special_block: special_json(&block.special, true),
        special_allow: special_json(&allow.special, false),
    };
    serde_json::to_string(&document).expect("a snapshot document is always serializable")
}

// --- classification ---------------------------------------------------------------------------

/// First-occurrence-ordered set; the Kotlin `LinkedHashSet`.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct OrderedSet {
    items: Vec<String>,
    seen: HashSet<String>,
}

impl OrderedSet {
    fn insert(&mut self, value: &str) {
        if self.seen.insert(value.to_string()) {
            self.items.push(value.to_string());
        }
    }

    fn extend(&mut self, values: &[String]) {
        for value in values {
            self.insert(value);
        }
    }

    fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

/// One package's exact/wildcard buckets.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct Bucket {
    exact: OrderedSet,
    important_exact: OrderedSet,
    wildcards: Vec<String>,
    important_wildcards: Vec<String>,
}

/// `HashMap` + key order, the Kotlin `HashMap<String, Bucket>` whose key order the export walks.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct Buckets {
    order: Vec<String>,
    index: HashMap<String, usize>,
    entries: Vec<Bucket>,
}

impl Buckets {
    fn entry(&mut self, package: &str) -> &mut Bucket {
        let position = match self.index.get(package) {
            Some(&position) => position,
            None => {
                let position = self.entries.len();
                self.index.insert(package.to_string(), position);
                self.order.push(package.to_string());
                self.entries.push(Bucket::default());
                position
            }
        };
        &mut self.entries[position]
    }

    fn get(&self, package: &str) -> Option<&Bucket> {
        self.index
            .get(package)
            .map(|&position| &self.entries[position])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Inverted {
    pattern: String,
    source: String,
    important: bool,
    excluded: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Special {
    pattern: String,
    source: String,
    important: bool,
    app_scope: Option<String>,
    app_inverted: bool,
    is_wildcard: bool,
    denyallow: Option<String>,
    is_regex: bool,
    dns_type: Option<String>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct Part {
    exact: OrderedSet,
    important_exact: OrderedSet,
    wildcards: Vec<String>,
    important_wildcards: Vec<String>,
    app_buckets: Buckets,
    inverted: Vec<Inverted>,
    special: Vec<Special>,
}

/// `nonEmpty` for the optional rule attributes (`null` and `""` both mean absent).
fn present(value: &Option<String>) -> bool {
    value.as_deref().is_some_and(|text| !text.is_empty())
}

/// The trimmed, lowercased package list of one `appScope`; duplicates are kept, exactly like
/// `appScopePackages()`.
fn app_scope_packages(scope: &str) -> Vec<String> {
    scope
        .split('|')
        .map(|package| package.trim().to_lowercase())
        .filter(|package| !package.is_empty())
        .collect()
}

/// `excludedApps()`: the same list as an ordered set.
fn excluded_apps(packages: &[String]) -> Vec<String> {
    let mut set = OrderedSet::default();
    set.extend(packages);
    set.items
}

/// Classifies one list of rows. `plain_gate` is `Some((index_usable, important_usable))` for
/// subscription rows, whose plain entries are already in the DTRI trie; custom rows pass `None`.
fn classify(rows: &[Row], plain_gate: Option<(bool, bool)>) -> Part {
    let mut part = Part::default();
    for row in rows {
        if row.is_regex || present(&row.denyallow) || present(&row.dns_type) {
            part.special.push(Special {
                pattern: row.pattern.clone(),
                source: row.source.clone(),
                important: row.important,
                app_scope: row.app_scope.clone(),
                app_inverted: row.app_inverted,
                is_wildcard: row.is_wildcard || row.pattern.contains('*'),
                denyallow: row.denyallow.clone(),
                is_regex: row.is_regex,
                dns_type: row.dns_type.clone(),
            });
            continue;
        }
        let wildcard = row.is_wildcard || row.pattern.contains('*');
        // `appScope.isNullOrEmpty()`: the empty string counts as "no scope", but "|" or " " do not,
        // even though their package list is empty (the rule is then dropped or inverted with an
        // empty exclusion set, exactly like the Kotlin branches).
        let has_scope = row
            .app_scope
            .as_deref()
            .is_some_and(|scope| !scope.is_empty());
        let packages = app_scope_packages(row.app_scope.as_deref().unwrap_or(""));
        if row.app_inverted && has_scope {
            part.inverted.push(Inverted {
                pattern: row.pattern.clone(),
                source: row.source.clone(),
                important: row.important,
                excluded: excluded_apps(&packages),
            });
            continue;
        }
        if has_scope {
            for package in packages {
                let bucket = part.app_buckets.entry(&package);
                match (wildcard, row.important) {
                    (true, true) => bucket.important_wildcards.push(row.pattern.clone()),
                    (true, false) => bucket.wildcards.push(row.pattern.clone()),
                    (false, true) => bucket.important_exact.insert(&row.pattern),
                    (false, false) => bucket.exact.insert(&row.pattern),
                }
            }
            continue;
        }
        if wildcard {
            if row.important {
                part.important_wildcards.push(row.pattern.clone());
            } else {
                part.wildcards.push(row.pattern.clone());
            }
            continue;
        }
        // A plain rule that the DTRI trie already holds is not repeated inline.
        let gate = plain_gate.unwrap_or((false, false));
        if row.important {
            if !gate.1 {
                part.important_exact.insert(&row.pattern);
            }
        } else if !gate.0 {
            part.exact.insert(&row.pattern);
        }
    }
    part
}

/// Everything one half learned, in the order the JSON needs it.
#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct Loaded {
    custom: Part,
    subscription: Part,
}

impl Loaded {
    fn block_export(&self) -> BlockExport {
        let mut global_block = OrderedSet::default();
        for part in [&self.custom, &self.subscription] {
            global_block.extend(&part.exact.items);
            global_block.extend(&part.wildcards);
        }
        let mut global_important = OrderedSet::default();
        for part in [&self.custom, &self.subscription] {
            global_important.extend(&part.important_exact.items);
            global_important.extend(&part.important_wildcards);
        }
        let mut app_rules = Vec::new();
        for package in package_order(&self.custom, &self.subscription) {
            let mut block = OrderedSet::default();
            let mut important = OrderedSet::default();
            for part in [&self.custom, &self.subscription] {
                if let Some(bucket) = part.app_buckets.get(package) {
                    block.extend(&bucket.exact.items);
                    block.extend(&bucket.wildcards);
                    important.extend(&bucket.important_exact.items);
                    important.extend(&bucket.important_wildcards);
                }
            }
            if !block.is_empty() || !important.is_empty() {
                app_rules.push(ExportedAppBlock {
                    package: package.to_string(),
                    block: block.items,
                    important: important.items,
                });
            }
        }
        BlockExport {
            global_block: global_block.items,
            global_important: global_important.items,
            app_rules,
            inverted: concatenate(&self.custom.inverted, &self.subscription.inverted),
            special: concatenate(&self.custom.special, &self.subscription.special),
        }
    }

    fn allow_export(&self) -> AllowExport {
        let mut global_allow = OrderedSet::default();
        for part in [&self.custom, &self.subscription] {
            global_allow.extend(&part.exact.items);
            global_allow.extend(&part.wildcards);
            global_allow.extend(&part.important_exact.items);
            global_allow.extend(&part.important_wildcards);
        }
        let mut app_rules = Vec::new();
        for package in package_order(&self.custom, &self.subscription) {
            let mut all = OrderedSet::default();
            for part in [&self.custom, &self.subscription] {
                if let Some(bucket) = part.app_buckets.get(package) {
                    all.extend(&bucket.exact.items);
                    all.extend(&bucket.important_exact.items);
                    all.extend(&bucket.wildcards);
                    all.extend(&bucket.important_wildcards);
                }
            }
            if !all.is_empty() {
                app_rules.push((package.to_string(), all.items));
            }
        }
        AllowExport {
            global_allow: global_allow.items,
            app_rules,
            inverted: concatenate(&self.custom.inverted, &self.subscription.inverted),
            special: concatenate(&self.custom.special, &self.subscription.special),
        }
    }
}

fn load(input: &LoadInput) -> Loaded {
    Loaded {
        custom: classify(&input.custom, None),
        subscription: classify(
            &input.subscription,
            Some((input.index_usable, input.important_usable)),
        ),
    }
}

fn package_order<'a>(custom: &'a Part, subscription: &'a Part) -> Vec<&'a str> {
    let mut order: Vec<&str> = Vec::new();
    let mut seen: HashSet<&str> = HashSet::new();
    for package in &custom.app_buckets.order {
        if seen.insert(package.as_str()) {
            order.push(package.as_str());
        }
    }
    for package in &subscription.app_buckets.order {
        if seen.insert(package.as_str()) {
            order.push(package.as_str());
        }
    }
    order
}

fn concatenate<T: Clone>(left: &[T], right: &[T]) -> Vec<T> {
    let mut out = Vec::with_capacity(left.len() + right.len());
    out.extend_from_slice(left);
    out.extend_from_slice(right);
    out
}

struct BlockExport {
    global_block: Vec<String>,
    global_important: Vec<String>,
    app_rules: Vec<ExportedAppBlock>,
    inverted: Vec<Inverted>,
    special: Vec<Special>,
}

struct AllowExport {
    global_allow: Vec<String>,
    app_rules: Vec<(String, Vec<String>)>,
    inverted: Vec<Inverted>,
    special: Vec<Special>,
}

struct ExportedAppBlock {
    package: String,
    block: Vec<String>,
    important: Vec<String>,
}

// --- the JSON document ------------------------------------------------------------------------

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SnapshotJson<'a> {
    filter_enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    block_trie_path: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    important_block_trie_path: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    allow_trie_path: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    important_allow_trie_path: Option<&'a str>,
    global_allow: Vec<String>,
    global_block: Vec<String>,
    global_important: Vec<String>,
    app_rules: std::collections::BTreeMap<String, AppRulesJson>,
    inverted_block: Vec<InvertedBlockJson<'a>>,
    inverted_allow: Vec<InvertedAllowJson<'a>>,
    disabled_rules: Vec<String>,
    special_block: Vec<SpecialJson<'a>>,
    special_allow: Vec<SpecialJson<'a>>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct AppRulesJson {
    allow: Vec<String>,
    block: Vec<String>,
    important: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct InvertedBlockJson<'a> {
    pattern: &'a str,
    source: &'a str,
    important: bool,
    excluded_apps: &'a [String],
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct InvertedAllowJson<'a> {
    pattern: &'a str,
    excluded_apps: &'a [String],
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SpecialJson<'a> {
    pattern: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    source: Option<&'a str>,
    important: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    app_scope: Option<&'a str>,
    app_inverted: bool,
    is_wildcard: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    denyallow: Option<&'a str>,
    is_regex: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    dns_type: Option<&'a str>,
}

fn special_json(special: &[Special], with_source: bool) -> Vec<SpecialJson<'_>> {
    special
        .iter()
        .map(|rule| SpecialJson {
            pattern: &rule.pattern,
            source: if with_source {
                Some(rule.source.as_str())
            } else {
                None
            },
            important: rule.important,
            app_scope: rule.app_scope.as_deref(),
            app_inverted: rule.app_inverted,
            is_wildcard: rule.is_wildcard,
            denyallow: rule.denyallow.as_deref(),
            is_regex: rule.is_regex,
            dns_type: rule.dns_type.as_deref(),
        })
        .collect()
}

/// `appRules`: the union of the allow buckets, the block buckets and the user per-app allowlist,
/// in that key order, with `allow` folding the user allowlist in.
fn app_rules_json(
    block: &BlockExport,
    allow: &AllowExport,
    app_allowlist: &[(String, Vec<String>)],
) -> std::collections::BTreeMap<String, AppRulesJson> {
    let mut order: Vec<String> = Vec::new();
    let mut seen: HashSet<String> = HashSet::new();
    for package in allow
        .app_rules
        .iter()
        .map(|(package, _)| package)
        .chain(block.app_rules.iter().map(|rules| &rules.package))
        .chain(app_allowlist.iter().map(|(package, _)| package))
    {
        if seen.insert(package.clone()) {
            order.push(package.clone());
        }
    }
    let mut app_rules = std::collections::BTreeMap::new();
    for package in order {
        let mut allows = OrderedSet::default();
        if let Some((_, rules)) = allow.app_rules.iter().find(|(name, _)| *name == package) {
            allows.extend(rules);
        }
        if let Some((_, domains)) = app_allowlist.iter().find(|(name, _)| *name == package) {
            allows.extend(domains);
        }
        let block_rules = block
            .app_rules
            .iter()
            .find(|rules| rules.package == package);
        app_rules.insert(
            package,
            AppRulesJson {
                allow: allows.items,
                block: block_rules
                    .map(|rules| rules.block.clone())
                    .unwrap_or_default(),
                important: block_rules
                    .map(|rules| rules.important.clone())
                    .unwrap_or_default(),
            },
        );
    }
    app_rules
}

#[cfg(test)]
mod tests;
