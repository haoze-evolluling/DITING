//! The rule index: four priority tiers, a bloom prefilter and the rewrite buckets.
//!
//! This is `RuleMatcher.BuildFromRules` + `RuleMatcher.Match` from the Go engine, plus the rewrite
//! selection of `rule_matcher_rewrite.go`. Priority order (`$dnsrewrite` > `$important` allow >
//! `$important` block > `@@` allow > block trie > wildcard/regex block) is unchanged, and so is the
//! tie-breaking inside a tier: trie first, then the pattern lists in rule order, first hit wins.
//!
//! Answer construction for a rewrite hit stays in Go: this crate reports *which* rules produced the
//! answer, Go turns their `RewriteAction` into `dns.RR`.

use std::collections::HashMap;

use crate::bloom::DomainBloomFilter;
use crate::rule::{Rule, RCODE_SUCCESS, TYPE_CNAME};
use crate::trie::DomainTrie;

/// What a query resolved to.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    /// No rule asked for anything.
    Pass,
    /// A whitelist rule let the name through.
    Allow,
    /// A blocklist rule stopped the name.
    Block,
    /// A `$dnsrewrite` rule answers the name itself.
    Rewrite,
}

/// Why the decision came out the way it did; the strings Go reports are derived from these.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Reason {
    ImportantAllow,
    ImportantBlock,
    Whitelist,
    Blacklist,
    WildcardBlock,
    RegexBlock,
}

impl Reason {
    /// Stable code for the FFI payload.
    pub fn code(self) -> u8 {
        match self {
            Reason::ImportantAllow => 0,
            Reason::ImportantBlock => 1,
            Reason::Whitelist => 2,
            Reason::Blacklist => 3,
            Reason::WildcardBlock => 4,
            Reason::RegexBlock => 5,
        }
    }
}

/// The rewrite answer of a hit: the response code plus the rules whose values make up the answer.
///
/// `rules` holds the rule indices in the order the Go engine aggregated them, which matters because
/// several `A` records of the same name are summed into one response. An empty `rules` with
/// [`RCODE_SUCCESS`] is the authoritative NODATA case.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RewriteAnswer {
    pub rcode: u8,
    pub rules: Vec<u32>,
}

/// One verdict.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Decision {
    pub action: Action,
    pub reason: Option<Reason>,
    pub rule: Option<u32>,
    pub rewrite: Option<RewriteAnswer>,
}

impl Decision {
    fn pass() -> Self {
        Self {
            action: Action::Pass,
            reason: None,
            rule: None,
            rewrite: None,
        }
    }

    fn verdict(action: Action, reason: Reason, rule: u32) -> Self {
        Self {
            action,
            reason: Some(reason),
            rule: Some(rule),
            rewrite: None,
        }
    }

    fn rewrite(rule: u32, rcode: u8, rules: Vec<u32>) -> Self {
        Self {
            action: Action::Rewrite,
            reason: None,
            rule: Some(rule),
            rewrite: Some(RewriteAnswer { rcode, rules }),
        }
    }
}

/// The built index. Immutable once built: a rule reload builds a new one.
pub struct FilterIndex {
    rules: Vec<Rule>,
    important_allow_trie: DomainTrie,
    important_allow_patterns: Vec<u32>,
    important_block_trie: DomainTrie,
    important_block_patterns: Vec<u32>,
    allow_trie: DomainTrie,
    allow_patterns: Vec<u32>,
    bloom: DomainBloomFilter,
    block_trie: DomainTrie,
    block_patterns: Vec<u32>,
    total_rules: u32,
    has_deny_allow: bool,
    rewrite_exact: HashMap<String, Vec<u32>>,
    rewrite_patterns: Vec<u32>,
    rewrite_cancels: Vec<u32>,
    uncompiled_patterns: u32,
}

impl FilterIndex {
    /// `BuildFromRules`.
    pub fn build(rules: Vec<Rule>) -> Self {
        let total_rules = rules.len() as u32;
        let mut important_allow_trie = DomainTrie::new();
        let mut important_allow_patterns = Vec::new();
        let mut important_block_trie = DomainTrie::new();
        let mut important_block_patterns = Vec::new();
        let mut allow_trie = DomainTrie::new();
        let mut allow_patterns = Vec::new();
        let mut block_trie = DomainTrie::new();
        let mut block_patterns = Vec::new();
        let mut block_domains: Vec<&str> = Vec::new();
        let mut has_deny_allow = false;
        let mut rewrite_exact: HashMap<String, Vec<u32>> = HashMap::new();
        let mut rewrite_patterns = Vec::new();
        let mut rewrite_cancels = Vec::new();

        for (index, rule) in rules.iter().enumerate() {
            let id = index as u32;
            // Rewrite rules leave the block/allow tiers entirely: a bare `$dnsrewrite` exception
            // cancels one rewrite, it must not turn the whole name into an allow rule.
            if rule.rewrite.is_some() {
                if rule.is_allow() {
                    rewrite_cancels.push(id);
                } else if rule.is_pattern() {
                    rewrite_patterns.push(id);
                } else {
                    rewrite_exact
                        .entry(rule.pattern.clone())
                        .or_default()
                        .push(id);
                }
                continue;
            }

            if !rule.is_allow() && (!rule.deny_allow.is_empty() || !rule.to.is_empty()) {
                has_deny_allow = true;
            }

            let (trie, patterns) = match (rule.is_allow(), rule.is_important()) {
                (true, true) => (&mut important_allow_trie, &mut important_allow_patterns),
                (true, false) => (&mut allow_trie, &mut allow_patterns),
                (false, true) => (&mut important_block_trie, &mut important_block_patterns),
                (false, false) => (&mut block_trie, &mut block_patterns),
            };
            if rule.is_pattern() {
                patterns.push(id);
                continue;
            }
            trie.insert(&rule.pattern, id, rule.is_exact());
            if !rule.is_allow() {
                block_domains.push(&rule.pattern);
            }
        }

        let mut bloom = DomainBloomFilter::new(block_domains.len() + 10, 0.001);
        for domain in &block_domains {
            bloom.add(domain);
        }

        let uncompiled_patterns = rules
            .iter()
            .filter(|rule| rule.is_pattern() && rule.regex.is_none())
            .count() as u32;

        Self {
            rules,
            important_allow_trie,
            important_allow_patterns,
            important_block_trie,
            important_block_patterns,
            allow_trie,
            allow_patterns,
            bloom,
            block_trie,
            block_patterns,
            total_rules,
            has_deny_allow,
            rewrite_exact,
            rewrite_patterns,
            rewrite_cancels,
            uncompiled_patterns,
        }
    }

    /// `RuleMatcher.Match`. `domain` is lowercase, trimmed and has no trailing dot.
    pub fn match_domain(&self, domain: &str, qtype: u16) -> Decision {
        if domain.is_empty() {
            return Decision::pass();
        }

        // 0. `$dnsrewrite` answers before any block or allow rule is consulted.
        if let Some(decision) = self.match_rewrite(domain, qtype) {
            return decision;
        }

        // 1. `$important` exceptions.
        if let Some(rule) = self.important_allow_trie.match_domain(domain) {
            if self.rules[rule as usize].dns_type_matches(qtype) {
                return Decision::verdict(Action::Allow, Reason::ImportantAllow, rule);
            }
        }
        if let Some(rule) =
            self.first_matching(&self.important_allow_patterns, domain, qtype, false)
        {
            return Decision::verdict(Action::Allow, Reason::ImportantAllow, rule);
        }

        // 2. `$important` blocklist.
        if let Some(rule) = self.important_block_trie.match_domain(domain) {
            if self.rules[rule as usize].applicable(domain, qtype) {
                return Decision::verdict(Action::Block, Reason::ImportantBlock, rule);
            }
        }
        if let Some(rule) = self.first_matching(&self.important_block_patterns, domain, qtype, true)
        {
            return Decision::verdict(Action::Block, Reason::ImportantBlock, rule);
        }

        // 3. `@@` exceptions.
        if let Some(rule) = self.allow_trie.match_domain(domain) {
            if self.rules[rule as usize].dns_type_matches(qtype) {
                return Decision::verdict(Action::Allow, Reason::Whitelist, rule);
            }
        }
        if let Some(rule) = self.first_matching(&self.allow_patterns, domain, qtype, false) {
            return Decision::verdict(Action::Allow, Reason::Whitelist, rule);
        }

        // 4. Blocklist trie, behind the bloom prefilter.
        if self.bloom.might_contain_domain_or_parent(domain) {
            if let Some(rule) = self.block_trie.match_domain(domain) {
                if self.rules[rule as usize].applicable(domain, qtype) {
                    return Decision::verdict(Action::Block, Reason::Blacklist, rule);
                }
            }
        }

        // 5. Blocklist wildcard and regex rules.
        if let Some(rule) = self.first_matching(&self.block_patterns, domain, qtype, true) {
            let reason = if self.rules[rule as usize].is_regex() {
                Reason::RegexBlock
            } else {
                Reason::WildcardBlock
            };
            return Decision::verdict(Action::Block, reason, rule);
        }

        Decision::pass()
    }

    /// First rule in list order whose pattern and type fit.
    ///
    /// `blocklist` selects `matchRuleApplicable` (type and exclusions) over `matchDNSType`: allow
    /// rules ignore `$denyallow=`/`$to=`, exactly like the Go engine did.
    fn first_matching(
        &self,
        candidates: &[u32],
        domain: &str,
        qtype: u16,
        blocklist: bool,
    ) -> Option<u32> {
        for rule in candidates {
            let rule_ref = &self.rules[*rule as usize];
            if !rule_ref.matches_pattern(domain) {
                continue;
            }
            let fits = if blocklist {
                rule_ref.applicable(domain, qtype)
            } else {
                rule_ref.dns_type_matches(qtype)
            };
            if fits {
                return Some(*rule);
            }
        }
        None
    }

    /// `collectRewriteRulesUnlocked` + `applyRewriteCancelsUnlocked` + `matchRewriteUnlocked`.
    fn match_rewrite(&self, domain: &str, qtype: u16) -> Option<Decision> {
        if self.rewrite_exact.is_empty() && self.rewrite_patterns.is_empty() {
            return None;
        }

        let mut rules = self.collect_rewrite_rules(domain);
        if !self.rewrite_cancels.is_empty() && !rules.is_empty() {
            rules = self.apply_cancels(rules, domain);
        }
        let first = *rules.first()?;

        // 1. A failure response wins over any record.
        for rule in &rules {
            let Some(action) = self.rules[*rule as usize].rewrite.as_ref() else {
                continue;
            };
            if action.rcode != RCODE_SUCCESS {
                return Some(Decision::rewrite(*rule, action.rcode, Vec::new()));
            }
        }

        // 2. CNAME wins over other record types: the alias is a property of the name itself.
        for rule in &rules {
            let Some(action) = self.rules[*rule as usize].rewrite.as_ref() else {
                continue;
            };
            if action.rrtype == TYPE_CNAME {
                return Some(Decision::rewrite(*rule, RCODE_SUCCESS, vec![*rule]));
            }
        }

        // 3. Same-type records are summed into one answer; no record of that type is NODATA.
        let answers: Vec<u32> = rules
            .iter()
            .copied()
            .filter(|rule| {
                self.rules[*rule as usize]
                    .rewrite
                    .as_ref()
                    .is_some_and(|action| action.rrtype == qtype)
            })
            .collect();
        Some(Decision::rewrite(first, RCODE_SUCCESS, answers))
    }

    /// Exact buckets from the name upwards (parents inherit unless the rule is exact), then the
    /// wildcard/regex rewrites in rule order.
    fn collect_rewrite_rules(&self, domain: &str) -> Vec<u32> {
        let mut out = Vec::new();
        let mut name = domain;
        loop {
            if let Some(bucket) = self.rewrite_exact.get(name) {
                for rule in bucket {
                    let rule_ref = &self.rules[*rule as usize];
                    if !rule_ref.is_exact() || rule_ref.pattern == domain {
                        out.push(*rule);
                    }
                }
            }
            match name.find('.') {
                Some(dot) => name = &name[dot + 1..],
                None => break,
            }
        }
        for rule in &self.rewrite_patterns {
            if self.rules[*rule as usize].matches_pattern(domain) {
                out.push(*rule);
            }
        }
        out
    }

    /// `applyRewriteCancelsUnlocked`: a bare exception clears everything, a valued one clears the
    /// rules with the same normalized action key.
    fn apply_cancels(&self, rules: Vec<u32>, domain: &str) -> Vec<u32> {
        let mut kept = rules;
        for cancel in &self.rewrite_cancels {
            let cancel_rule = &self.rules[*cancel as usize];
            let Some(cancel_action) = cancel_rule.rewrite.as_ref() else {
                continue;
            };
            if !cancel_rule.covers(domain) {
                continue;
            }
            if cancel_action.bare {
                return Vec::new();
            }
            kept.retain(|rule| {
                self.rules[*rule as usize]
                    .rewrite
                    .as_ref()
                    .is_none_or(|action| action.key != cancel_action.key)
            });
        }
        kept
    }

    pub fn rules(&self) -> &[Rule] {
        &self.rules
    }

    /// `TotalRules`: every rule handed to the build, including rewrite and pattern rules.
    pub fn total_rules(&self) -> u32 {
        self.total_rules
    }

    /// Whether any blocklist rule carries `$denyallow=`/`$to=`; reported for the Go-side fast path.
    pub fn has_deny_allow(&self) -> bool {
        self.has_deny_allow
    }

    /// Regex/wildcard rules whose pattern this engine could not compile (they never match).
    pub fn uncompiled_patterns(&self) -> u32 {
        self.uncompiled_patterns
    }
}

#[cfg(test)]
mod tests;
