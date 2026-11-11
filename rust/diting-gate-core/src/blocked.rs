//! `SetBlockedUIDs`: the CSV the UI pushes and the set the flow handlers ask about.
//!
//! The old Go code split on `,`, ran `strings.TrimSpace` and `strconv.Atoi` on each element and
//! kept only `uid > 0`. A malformed element (a non-number, an empty string, an overflow) was
//! simply dropped, never an error — the engine runs with whatever parsed.

use std::collections::HashSet;

use diting_go_compat::text::go_trim_space;

/// `UIDUnknown` in Go: an unattributable flow never matches an explicit rule.
pub const UID_UNKNOWN: i64 = -1;

/// One published blocked-UID set. Immutable once built.
#[derive(Debug, Default)]
pub struct BlockedUids {
    uids: HashSet<i64>,
}

impl BlockedUids {
    /// `SetBlockedUIDs`: parse the CSV, keep the positive integers.
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

    /// `isUIDBlocked`: the unknown UID is never blocked, matching the old early return.
    pub fn is_blocked(&self, uid: i64) -> bool {
        uid != UID_UNKNOWN && self.uids.contains(&uid)
    }

    /// Number of stored UIDs (test helper).
    pub fn len(&self) -> usize {
        self.uids.len()
    }

    /// True when the set is empty.
    pub fn is_empty(&self) -> bool {
        self.uids.is_empty()
    }
}

/// `strconv.Atoi` on a 64-bit `int`: optional sign, decimal digits, no underscores or spaces.
///
/// `str::parse::<i64>` has the same acceptance set (a leading `+` is allowed, `0x`/`_` are not,
/// overflow is an error), so it is the exact Go behaviour these UIDs go through.
fn parse_go_int(text: &str) -> Option<i64> {
    if text.is_empty() {
        return None;
    }
    text.parse::<i64>().ok()
}

#[cfg(test)]
mod tests;
