//! The alias-chain plan: a bounded, unique, cycle-aware list of targets to re-evaluate.

/// Hard upper bound on how deep a chain is followed (design: depth ≤ 8).
pub const DEFAULT_MAX_DEPTH: usize = 8;

/// What the engine should re-evaluate.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RecheckPlan {
    /// Unique, order-preserving targets to re-evaluate (normalized).
    pub targets: Vec<String>,
    /// The chain was longer than the depth cap; the tail was not followed.
    pub truncated: bool,
    /// A repeated target was seen (a CNAME loop); following stopped there.
    pub cycle: bool,
}

/// Normalizes one target: trim, lowercase, drop a single trailing dot; `None` for blanks.
fn normalize(name: &str) -> Option<String> {
    let value = name.trim().trim_end_matches('.').to_ascii_lowercase();
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

/// `plan`: dedupe and bound the targets.
///
/// `max_depth` is clamped to `1..=DEFAULT_MAX_DEPTH` so a caller cannot ask for an unbounded walk.
/// Duplicates are dropped in first-seen order; encountering an already-seen name means a loop, so
/// the walk stops and marks [`RecheckPlan::cycle`].
pub fn plan(names: &[String], max_depth: usize) -> RecheckPlan {
    let depth = max_depth.clamp(1, DEFAULT_MAX_DEPTH);
    let mut seen = std::collections::HashSet::new();
    let mut targets = Vec::new();
    let mut truncated = false;
    let mut cycle = false;

    for raw in names {
        let Some(name) = normalize(raw) else {
            continue;
        };
        if seen.contains(&name) {
            cycle = true;
            break;
        }
        if targets.len() >= depth {
            truncated = true;
            break;
        }
        seen.insert(name.clone());
        targets.push(name);
    }

    RecheckPlan {
        targets,
        truncated,
        cycle,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn names(items: &[&str]) -> Vec<String> {
        items.iter().map(|s| s.to_string()).collect()
    }

    #[test]
    fn dedupes_and_normalizes() {
        let plan = plan(&names(&["A.example.", "b.example", "a.EXAMPLE"]), 8);
        assert_eq!(plan.targets, vec!["a.example", "b.example"]);
        assert!(!plan.truncated);
    }

    #[test]
    fn caps_depth_and_flags_truncation() {
        let list: Vec<String> = (0..20).map(|i| format!("h{i}.example")).collect();
        let plan = plan(&list, 8);
        assert_eq!(plan.targets.len(), 8);
        assert!(plan.truncated);
        assert!(!plan.cycle);
    }

    #[test]
    fn clamps_depth_to_the_hard_max() {
        let list: Vec<String> = (0..20).map(|i| format!("h{i}")).collect();
        assert_eq!(plan(&list, 999).targets.len(), DEFAULT_MAX_DEPTH);
        assert_eq!(plan(&list, 0).targets.len(), 1);
    }

    #[test]
    fn detects_a_cycle() {
        let plan = plan(&names(&["a.example", "b.example", "a.example"]), 8);
        assert_eq!(plan.targets, vec!["a.example", "b.example"]);
        assert!(plan.cycle);
    }

    #[test]
    fn blanks_are_skipped() {
        let plan = plan(&names(&["", "   ", "real.example"]), 8);
        assert_eq!(plan.targets, vec!["real.example"]);
    }
}
