use std::collections::HashMap;

use crate::bloom::DomainBloomFilter;
use crate::rule::{Rule, RCODE_SUCCESS, TYPE_CNAME};
use crate::trie::DomainTrie;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Action {
    Pass,
    Allow,
    Block,
    Rewrite,
}

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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RewriteAnswer {
    pub rcode: u8,
    pub rules: Vec<u32>,
}

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
                // `*.foo.com` 的语义（任意层级子域命中、顶点不命中）与后缀树的 `*` 标签完全一致。
                // 原先这类规则被编译成正则并留在 `patterns`，于是**每个**未被 trie 命中的查询
                // 都要把全部通配规则逐条跑一遍 `regex.is_match`，几千条通配就是每次查询几百微秒。
                // 只有中缀星号 / 多星号 / 真正则才需要留在扫描列表里。
                // `regex.is_none()` 表示该通配规则编译失败，旧语义是永不匹配，故不能塞进 trie。
                if let Some(pattern) = leading_label_wildcard(&rule.pattern) {
                    if rule.regex.is_some() {
                        trie.insert(pattern, id, false);
                        if !rule.is_allow() {
                            // bloom 只索引去掉 `*` 的后缀，否则会把顶点也误判为可能命中。
                            block_domains.push(&pattern[2..]);
                        }
                        continue;
                    }
                }
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

    pub fn match_domain(&self, domain: &str, qtype: u16) -> Decision {
        if domain.is_empty() {
            return Decision::pass();
        }

        if let Some(decision) = self.match_rewrite(domain, qtype) {
            return decision;
        }

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

        if let Some(rule) = self.important_block_trie.match_domain(domain) {
            if self.rules[rule as usize].applicable(domain, qtype) {
                return Decision::verdict(Action::Block, Reason::ImportantBlock, rule);
            }
        }
        if let Some(rule) = self.first_matching(&self.important_block_patterns, domain, qtype, true)
        {
            return Decision::verdict(Action::Block, Reason::ImportantBlock, rule);
        }

        if let Some(rule) = self.allow_trie.match_domain(domain) {
            if self.rules[rule as usize].dns_type_matches(qtype) {
                return Decision::verdict(Action::Allow, Reason::Whitelist, rule);
            }
        }
        if let Some(rule) = self.first_matching(&self.allow_patterns, domain, qtype, false) {
            return Decision::verdict(Action::Allow, Reason::Whitelist, rule);
        }

        if self.bloom.might_contain_domain_or_parent(domain) {
            if let Some(rule) = self.block_trie.match_domain(domain) {
                let hit = &self.rules[rule as usize];
                if hit.applicable(domain, qtype) {
                    // 通配规则现在也走 trie，命中原因仍要如实区分，日志里才能看出是哪种规则。
                    let reason = if hit.is_wildcard() {
                        Reason::WildcardBlock
                    } else if hit.is_regex() {
                        Reason::RegexBlock
                    } else {
                        Reason::Blacklist
                    };
                    return Decision::verdict(Action::Block, reason, rule);
                }
            }
        }

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

    fn match_rewrite(&self, domain: &str, qtype: u16) -> Option<Decision> {
        if self.rewrite_exact.is_empty() && self.rewrite_patterns.is_empty() {
            return None;
        }

        let mut rules = self.collect_rewrite_rules(domain);
        if !self.rewrite_cancels.is_empty() && !rules.is_empty() {
            rules = self.apply_cancels(rules, domain);
        }
        let first = *rules.first()?;

        for rule in &rules {
            let Some(action) = self.rules[*rule as usize].rewrite.as_ref() else {
                continue;
            };
            if action.rcode != RCODE_SUCCESS {
                return Some(Decision::rewrite(*rule, action.rcode, Vec::new()));
            }
        }

        for rule in &rules {
            let Some(action) = self.rules[*rule as usize].rewrite.as_ref() else {
                continue;
            };
            if action.rrtype == TYPE_CNAME {
                return Some(Decision::rewrite(*rule, RCODE_SUCCESS, vec![*rule]));
            }
        }

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

    pub fn total_rules(&self) -> u32 {
        self.total_rules
    }

    pub fn has_deny_allow(&self) -> bool {
        self.has_deny_allow
    }

    pub fn uncompiled_patterns(&self) -> u32 {
        self.uncompiled_patterns
    }
}

/// 只有「首个标签是 `*`、其余部分不含 `*`」的通配能由后缀树精确表达。
/// `*.foo.com` 原样交给 trie 的 `*` 标签；`a.*.com`、`*a.foo.com` 之类仍留给正则。
fn leading_label_wildcard(pattern: &str) -> Option<&str> {
    let rest = pattern.strip_prefix("*.")?;
    if rest.is_empty() || rest.contains('*') {
        return None;
    }
    Some(pattern)
}

#[cfg(test)]
mod tests;
