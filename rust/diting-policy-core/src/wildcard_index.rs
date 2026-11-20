use std::collections::HashMap;

use crate::glob::WildcardMatcher;

const NO_MATCH: usize = usize::MAX;

struct Glob {
    order: usize,
    tail: String,
    matcher: std::sync::Arc<WildcardMatcher>,
}

struct Suffix {
    order: usize,
    pattern: String,
}

pub struct WildcardIndex {
    ordered: Vec<std::sync::Arc<WildcardMatcher>>,
    all_order: usize,
    all_pattern: String,
    suffix: HashMap<String, Suffix>,
    globs: HashMap<String, Vec<Glob>>,
    residual: Vec<Glob>,
}

impl WildcardIndex {
    pub fn new(ordered: Vec<std::sync::Arc<WildcardMatcher>>) -> Option<WildcardIndex> {
        if ordered.is_empty() {
            return None;
        }
        let mut index = WildcardIndex {
            ordered,
            all_order: NO_MATCH,
            all_pattern: String::new(),
            suffix: HashMap::new(),
            globs: HashMap::new(),
            residual: Vec::new(),
        };
        for order in 0..index.ordered.len() {
            let matcher = index.ordered[order].clone();
            index.add(order, matcher);
        }
        Some(index)
    }

    fn add(&mut self, order: usize, matcher: std::sync::Arc<WildcardMatcher>) {
        let pattern = matcher.pattern.clone();
        if matcher.is_all {
            if order < self.all_order {
                self.all_order = order;
                self.all_pattern = pattern;
            }
            return;
        }
        if !pattern.is_ascii() {
            self.residual.push(Glob {
                order,
                tail: String::new(),
                matcher,
            });
            return;
        }
        if let Some(rest) = pattern.strip_prefix("*.") {
            if !rest.contains('*') && !pattern.ends_with('.') && !matcher.base_domain.is_empty() {
                self.suffix
                    .entry(matcher.base_domain.clone())
                    .or_insert(Suffix {
                        order,
                        pattern: pattern.clone(),
                    });
                return;
            }
        }
        let tail = match pattern.rfind('*') {
            Some(position) => &pattern[position + 1..],
            None => pattern.as_str(),
        };
        if tail.ends_with('.') {
            self.residual.push(Glob {
                order,
                tail: tail.to_string(),
                matcher,
            });
            return;
        }
        if let Some(dot) = tail.find('.') {
            if dot < tail.len() - 1 {
                let key = tail[dot + 1..].to_string();
                self.globs.entry(key).or_default().push(Glob {
                    order,
                    tail: tail.to_string(),
                    matcher,
                });
                return;
            }
        }
        self.residual.push(Glob {
            order,
            tail: tail.to_string(),
            matcher,
        });
    }

    pub fn matches(&self, domain: &str) -> Option<&str> {
        if !domain.is_ascii() {
            for matcher in &self.ordered {
                if matcher.matches(domain) {
                    return Some(&matcher.pattern);
                }
            }
            return None;
        }
        let mut best = self.all_order;
        let mut best_pattern: &str = &self.all_pattern;
        let mut start = 0usize;
        loop {
            let d = &domain[start..];
            if !self.suffix.is_empty() {
                if let Some(entry) = self.suffix.get(d) {
                    if entry.order < best {
                        best = entry.order;
                        best_pattern = &entry.pattern;
                    }
                }
            }
            if !self.globs.is_empty() {
                if let Some(bucket) = self.globs.get(d) {
                    for glob in bucket {
                        if glob.order >= best {
                            break;
                        }
                        if domain.ends_with(&glob.tail) && glob.matcher.matches(domain) {
                            best = glob.order;
                            best_pattern = &glob.matcher.pattern;
                            break;
                        }
                    }
                }
            }
            let Some(relative) = domain[start..].find('.') else {
                break;
            };
            let dot = start + relative;
            if dot + 1 >= domain.len() {
                break;
            }
            start = dot + 1;
        }
        for glob in &self.residual {
            if glob.order >= best {
                break;
            }
            if domain.ends_with(&glob.tail) && glob.matcher.matches(domain) {
                best = glob.order;
                best_pattern = &glob.matcher.pattern;
                break;
            }
        }
        if best == NO_MATCH {
            return None;
        }
        Some(best_pattern)
    }
}

#[cfg(test)]
mod tests {
    use std::sync::Arc;

    use super::*;

    fn matchers(patterns: &[&str]) -> Vec<Arc<WildcardMatcher>> {
        patterns
            .iter()
            .filter_map(|pattern| WildcardMatcher::new(pattern))
            .map(Arc::new)
            .collect()
    }

    fn index(patterns: &[&str]) -> Option<WildcardIndex> {
        WildcardIndex::new(matchers(patterns))
    }

    fn linear(ordered: &[Arc<WildcardMatcher>], domain: &str) -> Option<String> {
        ordered
            .iter()
            .find(|matcher| matcher.matches(domain))
            .map(|matcher| matcher.pattern.clone())
    }

    #[test]
    fn index_equals_linear_scan() {
        let patterns = [
            "*.example.com",
            "ads*.example.org",
            "*tracker.net",
            "foo.*.com",
            "x*",
            "*-ad.*.cn",
            "*.b.com",
            "a*b.c.d",
            "*.example.com",
            "*.cn",
            "*ads",
            "*.xn--fiqs8s",
            "*.中国",
            "img*.cdn.*",
            "*.a..b",
            "*",
        ];
        let labels = [
            "a",
            "b",
            "com",
            "example",
            "org",
            "ads1",
            "adsx",
            "net",
            "tracker",
            "mytracker",
            "foo",
            "cn",
            "x-ad",
            "c",
            "d",
            "axb",
            "img2",
            "cdn",
            "xn--fiqs8s",
            "中国",
        ];
        let mut state: u64 = 0x9e3779b97f4a7c15;
        let mut next = |bound: usize| {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            (state % bound as u64) as usize
        };
        let all = matchers(&patterns);
        for round in 0..120 {
            let mut selected: Vec<Arc<WildcardMatcher>> = all
                .iter()
                .filter(|_| next(3) > 0 || round % 40 == 0)
                .cloned()
                .collect();
            for i in (1..selected.len()).rev() {
                selected.swap(i, next(i + 1));
            }
            let indexed = WildcardIndex::new(selected.clone());
            for _ in 0..200 {
                let mut domain = String::new();
                for i in 0..1 + next(4) {
                    if i > 0 {
                        domain.push('.');
                    }
                    domain.push_str(labels[next(labels.len())]);
                }
                let want = linear(&selected, &domain);
                let got = indexed.as_ref().and_then(|index| index.matches(&domain));
                assert_eq!(
                    got.map(str::to_string),
                    want,
                    "round {round} domain {domain:?}"
                );
            }
        }
    }

    #[test]
    fn trailing_dot_glob_keeps_the_go_prefilter_quirk() {
        let pattern = WildcardMatcher::new("*.foo.").unwrap();
        assert!(pattern.matches("foo"));
        let index = index(&["*.foo."]).unwrap();
        assert_eq!(index.matches("foo"), None);
        assert_eq!(index.matches("a.foo"), None);
    }

    #[test]
    fn empty_list_has_no_index() {
        assert!(WildcardIndex::new(Vec::new()).is_none());
    }

    #[test]
    fn all_wildcard_wins_on_an_empty_domain_miss() {
        let index = index(&["*.a.com", "*"]).unwrap();
        assert_eq!(index.matches("other.net"), Some("*"));
        assert_eq!(index.matches("x.a.com"), Some("*.a.com"));
    }
}
