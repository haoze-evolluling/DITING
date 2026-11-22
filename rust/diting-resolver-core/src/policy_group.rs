#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum GroupType {
    Select,
    UrlTest,
    Fallback,
    LoadBalance,
}

impl GroupType {
    pub fn parse(value: &str) -> GroupType {
        match value {
            "url-test" | "urltest" => GroupType::UrlTest,
            "fallback" => GroupType::Fallback,
            "load-balance" | "loadbalance" => GroupType::LoadBalance,
            _ => GroupType::Select,
        }
    }

    pub fn as_str(self) -> &'static str {
        match self {
            GroupType::Select => "select",
            GroupType::UrlTest => "url-test",
            GroupType::Fallback => "fallback",
            GroupType::LoadBalance => "load-balance",
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MemberReading {
    pub id: String,
    pub score_ns: i64,
    pub healthy: bool,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PolicyGroup {
    pub id: String,
    pub kind: GroupType,
    pub members: Vec<String>,
    pub fallback: Vec<String>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Selection {
    pub member: String,
    pub kind: GroupType,
    pub used_fallback: bool,
    pub reason: String,
}

fn reading<'a>(readings: &'a [MemberReading], id: &str) -> Option<&'a MemberReading> {
    readings.iter().find(|reading| reading.id == id)
}

fn choose_from(
    kind: GroupType,
    order: &[String],
    readings: &[MemberReading],
    seq: u64,
    used_fallback: bool,
) -> Option<Selection> {
    if order.is_empty() {
        return None;
    }
    let mut healthy: Vec<usize> = Vec::new();
    for (index, id) in order.iter().enumerate() {
        if reading(readings, id).map(|r| r.healthy).unwrap_or(false) {
            healthy.push(index);
        }
    }
    if healthy.is_empty() {
        return None;
    }
    let index = match kind {
        GroupType::Select => {
            if reading(readings, &order[0]).is_some() {
                0
            } else {
                healthy[0]
            }
        }
        GroupType::Fallback => healthy[0],
        GroupType::UrlTest => {
            let mut best = healthy[0];
            let mut best_score = reading(readings, &order[best])
                .map(|r| r.score_ns)
                .unwrap_or(i64::MAX);
            for &candidate in &healthy[1..] {
                let score = reading(readings, &order[candidate])
                    .map(|r| r.score_ns)
                    .unwrap_or(i64::MAX);
                if score < best_score {
                    best = candidate;
                    best_score = score;
                }
            }
            best
        }
        GroupType::LoadBalance => healthy[(seq as usize) % healthy.len()],
    };
    let member = order[index].clone();
    Some(Selection {
        member,
        kind,
        used_fallback,
        reason: if used_fallback {
            format!("主成员均不可用，回退链选中 {}", order[index])
        } else {
            format!("{} 策略选中 {}", kind.as_str(), order[index])
        },
    })
}

pub fn select(group: &PolicyGroup, readings: &[MemberReading], seq: u64) -> Option<Selection> {
    if let Some(selection) = choose_from(group.kind, &group.members, readings, seq, false) {
        return Some(selection);
    }
    choose_from(group.kind, &group.fallback, readings, seq, true)
}

impl Selection {
    pub fn kind_name(&self) -> &'static str {
        self.kind.as_str()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn group(kind: GroupType, members: &[&str], fallback: &[&str]) -> PolicyGroup {
        PolicyGroup {
            id: "g1".to_string(),
            kind,
            members: members.iter().map(|m| m.to_string()).collect(),
            fallback: fallback.iter().map(|m| m.to_string()).collect(),
        }
    }

    fn reading(id: &str, score_ms: i64, healthy: bool) -> MemberReading {
        MemberReading {
            id: id.to_string(),
            score_ns: score_ms * 1_000_000,
            healthy,
        }
    }

    #[test]
    fn select_takes_the_first_member() {
        let g = group(GroupType::Select, &["a", "b", "c"], &[]);
        let readings = vec![reading("a", 50, true), reading("b", 10, true)];
        let picked = select(&g, &readings, 0).unwrap();
        assert_eq!(picked.member, "a");
        assert!(!picked.used_fallback);
    }

    #[test]
    fn url_test_takes_the_lowest_score() {
        let g = group(GroupType::UrlTest, &["a", "b", "c"], &[]);
        let readings = vec![
            reading("a", 50, true),
            reading("b", 10, true),
            reading("c", 30, true),
        ];
        assert_eq!(select(&g, &readings, 0).unwrap().member, "b");
    }

    #[test]
    fn url_test_skips_unhealthy() {
        let g = group(GroupType::UrlTest, &["a", "b"], &[]);
        let readings = vec![reading("a", 5, false), reading("b", 40, true)];
        assert_eq!(select(&g, &readings, 0).unwrap().member, "b");
    }

    #[test]
    fn fallback_takes_first_healthy_in_order() {
        let g = group(GroupType::Fallback, &["a", "b", "c"], &[]);
        let readings = vec![
            reading("a", 5, false),
            reading("b", 50, true),
            reading("c", 1, true),
        ];
        assert_eq!(select(&g, &readings, 0).unwrap().member, "b");
    }

    #[test]
    fn load_balance_round_robins_by_sequence() {
        let g = group(GroupType::LoadBalance, &["a", "b"], &[]);
        let readings = vec![reading("a", 10, true), reading("b", 10, true)];
        assert_eq!(select(&g, &readings, 0).unwrap().member, "a");
        assert_eq!(select(&g, &readings, 1).unwrap().member, "b");
        assert_eq!(select(&g, &readings, 2).unwrap().member, "a");
    }

    #[test]
    fn fallback_chain_is_used_when_all_primary_are_down() {
        let g = group(GroupType::Fallback, &["a", "b"], &["reserve"]);
        let readings = vec![
            reading("a", 5, false),
            reading("b", 5, false),
            reading("reserve", 90, true),
        ];
        let picked = select(&g, &readings, 0).unwrap();
        assert_eq!(picked.member, "reserve");
        assert!(picked.used_fallback);
    }

    #[test]
    fn nothing_healthy_and_no_fallback_is_none() {
        let g = group(GroupType::UrlTest, &["a", "b"], &[]);
        let readings = vec![reading("a", 5, false), reading("b", 5, false)];
        assert!(select(&g, &readings, 0).is_none());
    }

    #[test]
    fn missing_member_reading_is_absent() {
        let g = group(GroupType::UrlTest, &["ghost", "b"], &[]);
        let readings = vec![reading("b", 40, true)];
        assert_eq!(select(&g, &readings, 0).unwrap().member, "b");
    }

    #[test]
    fn group_type_parses_aliases() {
        assert_eq!(GroupType::parse("url-test"), GroupType::UrlTest);
        assert_eq!(GroupType::parse("urltest"), GroupType::UrlTest);
        assert_eq!(GroupType::parse("loadbalance"), GroupType::LoadBalance);
        assert_eq!(GroupType::parse("whatever"), GroupType::Select);
    }
}
