//! `policySnapshot`: building the rule tables and running the seven-level decision walk
//! (`policy_snapshot.go` + `applySnapshot` in `policy_engine.go`).
//!
//! This is the part of the Go engine that moved to Rust: Go keeps the lifecycle (decoding the
//! payload for its error contract, swapping the atomic snapshot, the decision cache and the
//! fallback copy of this walk) and Rust owns the matching tables, the wildcard index, the DTRI
//! lookup and the priority order. The pieces live next door: [`crate::tables`] holds the buckets
//! and matching helpers, [`crate::decision`] the verdict type.
//!
//! The input domain is already normalized by the caller (`normalizePolicyDomain`: lowercase,
//! trimmed, no trailing dot) and the app name is already trimmed, so nothing here allocates for a
//! plain miss beyond what a lookup needs.

use std::collections::HashMap;
use std::sync::Arc;

use crate::decision::Decision;
use crate::dtri_read::DtriReader;
use crate::json::RuleSnapshot;
use crate::special::SpecialRule;
use crate::tables::{
    inverted_matches, match_domain_or_suffix, match_domain_or_suffix_set, open_trie,
    parse_inverted, parse_special, skipped_inverted, wildcard_list, AppRuleBucket, GlobSlot,
    InvertedRule,
};
use crate::text::{go_lower, go_lower_trim};
use crate::wildcard_index::WildcardIndex;

/// `policySnapshot`, without the Go-side decision cache (that stays in Go).
pub struct Snapshot {
    filter_enabled: bool,
    has_rules: bool,

    global_important: HashMap<String, String>,
    global_important_wildcards: Option<WildcardIndex>,
    important_inverted: Vec<InvertedRule>,
    important_block_trie: Option<Arc<DtriReader>>,

    global_allow: HashMap<String, ()>,
    global_allow_wildcards: Option<WildcardIndex>,
    allow_inverted: Vec<InvertedRule>,
    important_allow_trie: Option<Arc<DtriReader>>,
    allow_trie: Option<Arc<DtriReader>>,

    global_block: HashMap<String, String>,
    global_block_wildcards: Option<WildcardIndex>,
    block_inverted: Vec<InvertedRule>,
    block_trie: Option<Arc<DtriReader>>,

    important_app_block_special: Vec<SpecialRule>,
    important_global_block_special: Vec<SpecialRule>,
    app_allow_special: Vec<SpecialRule>,
    global_allow_special: Vec<SpecialRule>,
    app_block_special: Vec<SpecialRule>,
    global_block_special: Vec<SpecialRule>,

    disabled_rules: HashMap<String, ()>,
    app_buckets: HashMap<String, AppRuleBucket>,

    app_sensitive: bool,
    qtype_sensitive: bool,
}

impl Snapshot {
    /// `applySnapshot`: builds every table, collecting the regex rules the Rust engine compiled.
    /// The caller compares that count with Go's to detect an accept-set difference.
    pub fn build(request: &RuleSnapshot) -> (Snapshot, usize) {
        let filter_enabled = request.filter_enabled.unwrap_or(true);
        let mut snapshot = Snapshot {
            filter_enabled,
            has_rules: false,
            global_important: HashMap::new(),
            global_important_wildcards: None,
            important_inverted: Vec::new(),
            important_block_trie: None,
            global_allow: HashMap::new(),
            global_allow_wildcards: None,
            allow_inverted: Vec::new(),
            important_allow_trie: None,
            allow_trie: None,
            global_block: HashMap::new(),
            global_block_wildcards: None,
            block_inverted: Vec::new(),
            block_trie: None,
            important_app_block_special: Vec::new(),
            important_global_block_special: Vec::new(),
            app_allow_special: Vec::new(),
            global_allow_special: Vec::new(),
            app_block_special: Vec::new(),
            global_block_special: Vec::new(),
            disabled_rules: HashMap::new(),
            app_buckets: HashMap::new(),
            app_sensitive: false,
            qtype_sensitive: false,
        };

        for pattern in request.strings(&request.disabled_rules) {
            let pattern = go_lower_trim(pattern);
            if !pattern.is_empty() {
                snapshot.disabled_rules.insert(pattern, ());
            }
        }

        let mut important_wildcards = Vec::new();
        let mut allow_wildcards = Vec::new();
        let mut block_wildcards = Vec::new();
        snapshot.collect_global(
            request.strings(&request.global_important),
            GlobSlot::Important(&mut important_wildcards),
        );
        snapshot.collect_global(
            request.strings(&request.global_allow),
            GlobSlot::Allow(&mut allow_wildcards),
        );
        snapshot.collect_global(
            request.strings(&request.global_block),
            GlobSlot::Block(&mut block_wildcards),
        );

        if let Some(app_rules) = request.app_rules.as_ref() {
            for (package, config) in app_rules {
                let package = go_lower_trim(package);
                if package.is_empty() {
                    continue;
                }
                let mut bucket = AppRuleBucket::default();
                let mut bucket_allow = Vec::new();
                let mut bucket_block = Vec::new();
                let mut bucket_important = Vec::new();
                for pattern in config.allow.as_deref().unwrap_or(&[]) {
                    let pattern = go_lower_trim(pattern);
                    if pattern.is_empty() {
                        continue;
                    }
                    if pattern.contains('*') {
                        wildcard_list(std::slice::from_ref(&pattern), &mut bucket_allow);
                    } else {
                        bucket.allow.insert(pattern, ());
                    }
                }
                for pattern in config.block.as_deref().unwrap_or(&[]) {
                    let pattern = go_lower_trim(pattern);
                    if pattern.is_empty() {
                        continue;
                    }
                    if pattern.contains('*') {
                        wildcard_list(std::slice::from_ref(&pattern), &mut bucket_block);
                    } else {
                        bucket.block.insert(pattern.clone(), pattern);
                    }
                }
                for pattern in config.important.as_deref().unwrap_or(&[]) {
                    let pattern = go_lower_trim(pattern);
                    if pattern.is_empty() {
                        continue;
                    }
                    if pattern.contains('*') {
                        wildcard_list(std::slice::from_ref(&pattern), &mut bucket_important);
                    } else {
                        bucket
                            .important
                            .insert(pattern.clone(), "important".to_string());
                    }
                }
                bucket.allow_wildcards = WildcardIndex::new(bucket_allow);
                bucket.block_wildcards = WildcardIndex::new(bucket_block);
                bucket.important_wildcards = WildcardIndex::new(bucket_important);
                snapshot.app_buckets.insert(package, bucket);
            }
        }

        snapshot.global_important_wildcards = WildcardIndex::new(important_wildcards);
        snapshot.global_allow_wildcards = WildcardIndex::new(allow_wildcards);
        snapshot.global_block_wildcards = WildcardIndex::new(block_wildcards);

        for inverted in request.inverted_block.as_deref().unwrap_or(&[]) {
            if let Some(rule) = parse_inverted(inverted) {
                if inverted.important.unwrap_or(false) {
                    snapshot.important_inverted.push(rule);
                } else {
                    snapshot.block_inverted.push(rule);
                }
            }
        }
        for inverted in request.inverted_allow.as_deref().unwrap_or(&[]) {
            if let Some(rule) = parse_inverted(inverted) {
                snapshot.allow_inverted.push(rule);
            }
        }

        let mut regex_compiled = 0usize;
        for config in request.special_block.as_deref().unwrap_or(&[]) {
            let Some(rule) = parse_special(config, false, &mut regex_compiled) else {
                continue;
            };
            let has_app_scope = !rule.app_scope.is_empty();
            if rule.important {
                if has_app_scope && !rule.app_inverted {
                    snapshot.important_app_block_special.push(rule);
                } else {
                    snapshot.important_global_block_special.push(rule);
                }
            } else if has_app_scope && !rule.app_inverted {
                snapshot.app_block_special.push(rule);
            } else {
                snapshot.global_block_special.push(rule);
            }
        }
        for config in request.special_allow.as_deref().unwrap_or(&[]) {
            let Some(rule) = parse_special(config, true, &mut regex_compiled) else {
                continue;
            };
            let has_app_scope = !rule.app_scope.is_empty();
            if has_app_scope && !rule.app_inverted {
                snapshot.app_allow_special.push(rule);
            } else {
                snapshot.global_allow_special.push(rule);
            }
        }

        snapshot.block_trie = open_trie(request.block_trie_path.as_deref());
        snapshot.important_block_trie = open_trie(request.important_block_trie_path.as_deref());
        snapshot.important_allow_trie = open_trie(request.important_allow_trie_path.as_deref());
        snapshot.allow_trie = open_trie(request.allow_trie_path.as_deref());

        snapshot.has_rules = !snapshot.global_important.is_empty()
            || snapshot.global_important_wildcards.is_some()
            || !snapshot.important_inverted.is_empty()
            || snapshot.important_block_trie.is_some()
            || !snapshot.global_allow.is_empty()
            || snapshot.global_allow_wildcards.is_some()
            || !snapshot.allow_inverted.is_empty()
            || snapshot.important_allow_trie.is_some()
            || snapshot.allow_trie.is_some()
            || !snapshot.global_block.is_empty()
            || snapshot.global_block_wildcards.is_some()
            || !snapshot.block_inverted.is_empty()
            || snapshot.block_trie.is_some()
            || !snapshot.app_buckets.is_empty()
            || !snapshot.important_app_block_special.is_empty()
            || !snapshot.important_global_block_special.is_empty()
            || !snapshot.app_allow_special.is_empty()
            || !snapshot.global_allow_special.is_empty()
            || !snapshot.app_block_special.is_empty()
            || !snapshot.global_block_special.is_empty();

        snapshot.finalize_lookup();
        (snapshot, regex_compiled)
    }

    fn collect_global(&mut self, patterns: &[String], slot: GlobSlot<'_>) {
        match slot {
            GlobSlot::Important(wildcards) => {
                for pattern in patterns {
                    let pattern = go_lower_trim(pattern);
                    if pattern.is_empty() {
                        continue;
                    }
                    if pattern.contains('*') {
                        wildcard_list(std::slice::from_ref(&pattern), wildcards);
                    } else {
                        self.global_important
                            .insert(pattern, "important".to_string());
                    }
                }
            }
            GlobSlot::Allow(wildcards) => {
                for pattern in patterns {
                    let pattern = go_lower_trim(pattern);
                    if pattern.is_empty() {
                        continue;
                    }
                    if pattern.contains('*') {
                        wildcard_list(std::slice::from_ref(&pattern), wildcards);
                    } else {
                        self.global_allow.insert(pattern, ());
                    }
                }
            }
            GlobSlot::Block(wildcards) => {
                for pattern in patterns {
                    let pattern = go_lower_trim(pattern);
                    if pattern.is_empty() {
                        continue;
                    }
                    if pattern.contains('*') {
                        wildcard_list(std::slice::from_ref(&pattern), wildcards);
                    } else {
                        self.global_block.insert(pattern.clone(), pattern);
                    }
                }
            }
        }
    }

    /// `finalizeLookup`: which dimensions the decision cache has to keep apart.
    fn finalize_lookup(&mut self) {
        self.app_sensitive = !self.app_buckets.is_empty();
        for list in [
            &self.important_inverted,
            &self.allow_inverted,
            &self.block_inverted,
        ] {
            for rule in list {
                if !rule.excluded_apps.is_empty() {
                    self.app_sensitive = true;
                }
            }
        }
        for list in [
            &self.important_app_block_special,
            &self.important_global_block_special,
            &self.app_allow_special,
            &self.global_allow_special,
            &self.app_block_special,
            &self.global_block_special,
        ] {
            for rule in list {
                if !rule.app_scope.is_empty() {
                    self.app_sensitive = true;
                }
                if !rule.include_qtypes.is_empty() || !rule.exclude_qtypes.is_empty() {
                    self.qtype_sensitive = true;
                }
            }
        }
    }

    /// Flags used by the Go caller: bit0 `hasRules`, bit1 `appSensitive`, bit2 `qtypeSensitive`.
    pub fn flags(&self) -> u32 {
        let mut flags = 0;
        if self.has_rules {
            flags |= 1;
        }
        if self.app_sensitive {
            flags |= 2;
        }
        if self.qtype_sensitive {
            flags |= 4;
        }
        flags
    }

    /// `evaluateNormalized`: the seven priority levels, in order.
    pub fn evaluate<'a>(&'a self, domain: &str, app_name: &str, qtype: u16) -> Decision<'a> {
        if !self.filter_enabled {
            return Decision::pass();
        }
        if domain.is_empty() {
            return Decision::pass();
        }

        // Level 1: app-specific $important blocks.
        if !app_name.is_empty() {
            if let Some(bucket) = self.app_buckets.get(app_name) {
                if let Some(reason) = match_domain_or_suffix(domain, &bucket.important) {
                    return Decision::block(reason);
                }
                if let Some(pattern) = bucket
                    .important_wildcards
                    .as_ref()
                    .and_then(|index| index.matches(domain))
                {
                    return Decision::block(pattern);
                }
            }
        }
        for rule in &self.important_app_block_special {
            if rule.matches(domain, app_name, qtype) {
                return Decision::block(&rule.pattern);
            }
        }

        // Level 2: global $important blocks.
        for rule in &self.important_inverted {
            if skipped_inverted(rule, app_name) {
                continue;
            }
            if inverted_matches(rule, domain) {
                return Decision::block(&rule.pattern);
            }
        }
        for rule in &self.important_global_block_special {
            if rule.matches(domain, app_name, qtype) {
                return Decision::block(&rule.pattern);
            }
        }
        if let Some(reason) = match_domain_or_suffix(domain, &self.global_important) {
            return Decision::block(reason);
        }
        if let Some(pattern) = self
            .global_important_wildcards
            .as_ref()
            .and_then(|index| index.matches(domain))
        {
            return Decision::block(pattern);
        }
        if let Some(source) = self.important_block_trie.as_ref().and_then(|trie| {
            trie.contains_or_parent_with_disabled(domain, Some(&self.disabled_rules))
        }) {
            return Decision::block(source);
        }

        // Level 3: app-specific whitelist.
        if !app_name.is_empty() {
            if let Some(bucket) = self.app_buckets.get(app_name) {
                if match_domain_or_suffix_set(domain, &bucket.allow) {
                    return Decision::allow();
                }
                if bucket
                    .allow_wildcards
                    .as_ref()
                    .is_some_and(|index| index.matches(domain).is_some())
                {
                    return Decision::allow();
                }
            }
        }
        for rule in &self.app_allow_special {
            if rule.matches(domain, app_name, qtype) {
                return Decision::allow();
            }
        }

        // Level 4: global whitelist.
        for rule in &self.allow_inverted {
            if skipped_inverted(rule, app_name) {
                continue;
            }
            if inverted_matches(rule, domain) {
                return Decision::allow();
            }
        }
        for rule in &self.global_allow_special {
            if rule.matches(domain, app_name, qtype) {
                return Decision::allow();
            }
        }
        if match_domain_or_suffix_set(domain, &self.global_allow) {
            return Decision::allow();
        }
        if self
            .global_allow_wildcards
            .as_ref()
            .is_some_and(|index| index.matches(domain).is_some())
        {
            return Decision::allow();
        }
        if self
            .important_allow_trie
            .as_ref()
            .is_some_and(|trie| trie.contains_or_parent(domain).is_some())
        {
            return Decision::allow();
        }
        if self
            .allow_trie
            .as_ref()
            .is_some_and(|trie| trie.contains_or_parent(domain).is_some())
        {
            return Decision::allow();
        }

        // Level 5: app-specific normal blocks.
        if !app_name.is_empty() {
            if let Some(bucket) = self.app_buckets.get(app_name) {
                if let Some(reason) = match_domain_or_suffix(domain, &bucket.block) {
                    return Decision::block(reason);
                }
                if let Some(pattern) = bucket
                    .block_wildcards
                    .as_ref()
                    .and_then(|index| index.matches(domain))
                {
                    return Decision::block(pattern);
                }
            }
        }
        for rule in &self.app_block_special {
            if rule.matches(domain, app_name, qtype) {
                return Decision::block(&rule.pattern);
            }
        }

        // Level 6: global normal blocks.
        for rule in &self.block_inverted {
            if skipped_inverted(rule, app_name) {
                continue;
            }
            if inverted_matches(rule, domain) {
                return Decision::block(&rule.pattern);
            }
        }
        for rule in &self.global_block_special {
            if rule.matches(domain, app_name, qtype) {
                return Decision::block(&rule.pattern);
            }
        }
        if let Some(reason) = match_domain_or_suffix(domain, &self.global_block) {
            return Decision::block(reason);
        }
        if let Some(pattern) = self
            .global_block_wildcards
            .as_ref()
            .and_then(|index| index.matches(domain))
        {
            return Decision::block(pattern);
        }
        if let Some(source) = self.block_trie.as_ref().and_then(|trie| {
            trie.contains_or_parent_with_disabled(domain, Some(&self.disabled_rules))
        }) {
            return Decision::block(source);
        }

        // Level 7: default pass.
        Decision::pass()
    }
}

/// Lowercased rule text, exposed for the parity test that pins `strings.ToLower`.
pub fn debug_lower(input: &str) -> String {
    go_lower(input).into_owned()
}
