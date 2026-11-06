//! `DomainBloomFilter`: the prefilter in front of the block trie.
//!
//! Same shape as the Go type it replaces - double hashing with FNV-1a and FNV-1, `k` probes per
//! name, and a hierarchical probe that walks the parent domains. Its only job is to reject clean
//! names in nanoseconds before the trie walk; it never decides a match, so a false positive costs
//! one walk and a false negative would be impossible by construction (every blocking domain is
//! added, and the hierarchical probe visits every suffix the trie could match).

const FNV_OFFSET64: u64 = 14_695_981_039_346_656_037;
const FNV_PRIME64: u64 = 1_099_511_628_211;

/// `OptimalBloomParams`: bit count and probe count for `expected_items` at `fp_rate`.
pub fn optimal_params(expected_items: usize, fp_rate: f64) -> (u64, u32) {
    let expected_items = expected_items.max(1) as f64;
    let fp_rate = if fp_rate <= 0.0 || fp_rate >= 1.0 {
        0.001
    } else {
        fp_rate
    };
    let ln2 = std::f64::consts::LN_2;
    let mut bit_count = (-expected_items * fp_rate.ln() / (ln2 * ln2)).ceil() as u64;
    let hash_count = (((bit_count as f64 / expected_items) * ln2).ceil() as u32).max(1);
    if !bit_count.is_multiple_of(8) {
        bit_count = (bit_count / 8 + 1) * 8;
    }
    (bit_count, hash_count)
}

/// `DomainBloomFilter`.
#[derive(Debug, Default, Clone)]
pub struct DomainBloomFilter {
    bits: Vec<u8>,
    bit_count: u64,
    hash_count: u32,
}

impl DomainBloomFilter {
    pub fn new(expected_items: usize, fp_rate: f64) -> Self {
        let (bit_count, hash_count) = optimal_params(expected_items, fp_rate);
        Self {
            bits: vec![0; (bit_count / 8) as usize],
            bit_count,
            hash_count,
        }
    }

    /// `Add`: the domain is already normalized by the caller.
    pub fn add(&mut self, domain: &str) {
        if domain.is_empty() || self.bit_count == 0 {
            return;
        }
        let (h1, h2) = double_hash(domain);
        for probe in 0..self.hash_count {
            let index = (h1.wrapping_add(u64::from(probe).wrapping_mul(h2))) % self.bit_count;
            self.bits[(index / 8) as usize] |= 1 << (index % 8);
        }
    }

    /// `MightContain`: false means the name is definitely not in the set.
    pub fn might_contain(&self, domain: &str) -> bool {
        // An unbuilt filter fails open, exactly like the Go version did.
        if self.bit_count == 0 || self.bits.is_empty() {
            return true;
        }
        if domain.is_empty() {
            return false;
        }
        let (h1, h2) = double_hash(domain);
        for probe in 0..self.hash_count {
            let index = (h1.wrapping_add(u64::from(probe).wrapping_mul(h2))) % self.bit_count;
            let byte = (index / 8) as usize;
            match self.bits.get(byte) {
                Some(value) => {
                    if value & (1 << (index % 8)) == 0 {
                        return false;
                    }
                }
                // Mirrors the Go bounds check: a corrupted bitmap also fails open.
                None => return true,
            }
        }
        true
    }

    /// `MightContainDomainOrParent`: probes the name and every parent suffix.
    pub fn might_contain_domain_or_parent(&self, domain: &str) -> bool {
        if domain.is_empty() {
            return false;
        }
        let mut rest = domain;
        loop {
            if self.might_contain(rest) {
                return true;
            }
            match rest.find('.') {
                Some(dot) => rest = &rest[dot + 1..],
                None => return false,
            }
        }
    }
}

fn double_hash(value: &str) -> (u64, u64) {
    let mut h1 = FNV_OFFSET64;
    for byte in value.as_bytes() {
        h1 ^= u64::from(*byte);
        h1 = h1.wrapping_mul(FNV_PRIME64);
    }
    let mut h2 = FNV_OFFSET64;
    for byte in value.as_bytes() {
        h2 = h2.wrapping_mul(FNV_PRIME64);
        h2 ^= u64::from(*byte);
    }
    if h2.is_multiple_of(2) {
        h2 += 1;
    }
    (h1, h2)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn optimal_params_follow_the_go_formula() {
        // 1000 items at 0.1%: m = 14378 bits rounded up to a byte boundary, k = 10.
        let (bit_count, hash_count) = optimal_params(1000, 0.001);
        assert_eq!(bit_count, 14384);
        assert_eq!(hash_count, 10);
        assert!(bit_count.is_multiple_of(8));
        // Degenerate inputs are clamped, not rejected.
        let (bit_count, hash_count) = optimal_params(0, 0.0);
        assert!(bit_count >= 8);
        assert!(hash_count >= 1);
    }

    #[test]
    fn added_domains_and_their_parents_are_remembered() {
        let mut bloom = DomainBloomFilter::new(50, 0.001);
        bloom.add("ad.google.com");
        bloom.add("track.analytics.com");
        assert!(bloom.might_contain("ad.google.com"));
        assert!(bloom.might_contain_domain_or_parent("sub.ad.google.com"));
        assert!(!bloom.might_contain("clean-domain-random-12345.org"));
        assert!(!bloom.might_contain_domain_or_parent("clean-domain-random-12345.org"));
        assert!(!bloom.might_contain(""));
        assert!(!bloom.might_contain_domain_or_parent(""));
    }

    #[test]
    fn an_empty_filter_fails_open() {
        let bloom = DomainBloomFilter::default();
        assert!(bloom.might_contain("anything.test"));
    }

    #[test]
    fn no_false_negatives_over_a_mixed_corpus() {
        let domains: Vec<String> = (0..500)
            .map(|index| format!("host{index}.ad{}.example.com", index % 17))
            .collect();
        let mut bloom = DomainBloomFilter::new(domains.len(), 0.001);
        for domain in &domains {
            bloom.add(domain);
        }
        for domain in &domains {
            assert!(bloom.might_contain(domain), "{domain}");
            // Every added name must also pass the hierarchical probe used on the hot path.
            assert!(bloom.might_contain_domain_or_parent(domain), "{domain}");
        }
    }
}
