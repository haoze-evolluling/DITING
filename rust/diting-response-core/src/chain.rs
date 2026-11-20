pub const DEFAULT_MAX_DEPTH: usize = 8;

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RecheckPlan {
    pub targets: Vec<String>,
    pub truncated: bool,
    pub cycle: bool,
}

fn normalize(name: &str) -> Option<String> {
    let value = name.trim().trim_end_matches('.').to_ascii_lowercase();
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}

pub fn plan(names: &[String], max_depth: usize) -> RecheckPlan {
    plan_strs(names.iter().map(String::as_str), max_depth)
}

pub fn plan_strs<'a>(names: impl IntoIterator<Item = &'a str>, max_depth: usize) -> RecheckPlan {
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
    fn the_borrowed_form_matches_the_owned_one() {
        let borrowed = ["A.example.", "b.example", "b.example"];
        let owned = names(&["A.example.", "b.example", "b.example"]);
        assert_eq!(plan_strs(borrowed.iter().copied(), 8), plan(&owned, 8));
    }

    #[test]
    fn blanks_are_skipped() {
        let plan = plan(&names(&["", "   ", "real.example"]), 8);
        assert_eq!(plan.targets, vec!["real.example"]);
    }
}
