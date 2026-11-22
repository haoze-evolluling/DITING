use std::collections::HashSet;

use diting_go_compat::text::go_trim_space;

pub const UID_UNKNOWN: i64 = -1;

#[derive(Debug, Default)]
pub struct BlockedUids {
    uids: HashSet<i64>,
}

impl BlockedUids {
    pub fn parse_csv(csv: &str) -> Self {
        let mut uids = HashSet::new();
        for raw in csv.split(',') {
            let text = go_trim_space(raw);
            let Some(uid) = parse_go_int(text) else {
                continue;
            };
            if uid > 0 {
                uids.insert(uid);
            }
        }
        Self { uids }
    }

    pub fn is_blocked(&self, uid: i64) -> bool {
        uid != UID_UNKNOWN && self.uids.contains(&uid)
    }

    pub fn len(&self) -> usize {
        self.uids.len()
    }

    pub fn is_empty(&self) -> bool {
        self.uids.is_empty()
    }
}

fn parse_go_int(text: &str) -> Option<i64> {
    if text.is_empty() {
        return None;
    }
    text.parse::<i64>().ok()
}

#[cfg(test)]
mod tests;
