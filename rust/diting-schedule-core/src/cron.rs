//! A 5-field cron: `minute hour day-of-month month day-of-week`.
//!
//! Each field accepts `*`, `*/step`, `a`, `a-b`, `a-b/step` and comma lists of those. Day-of-week
//! is `0..=6` with Sunday as `0`; `7` is accepted and folded to Sunday. Occurrences land on minute
//! boundaries in the `civil` frame (see [`crate::civil`]), so a DST jump is handled by the caller
//! mapping civil↔UTC, not here. The search is bounded so a malformed or impossible expression
//! (e.g. `0 0 30 2 *`) cannot spin forever.

use crate::civil::{self, Civil, MINUTE_MS};

/// Five years of minutes; long enough for a leap-year February 29th expression.
const MAX_SEARCH_MINUTES: i64 = 366 * 24 * 60 * 5;

/// A parsed cron expression.
#[derive(Debug, Clone)]
pub struct Cron {
    minutes: Vec<bool>,
    hours: Vec<bool>,
    days_of_month: Vec<bool>,
    months: Vec<bool>,
    days_of_week: Vec<bool>,
}

/// Parses one field into a membership table indexed by value.
fn parse_field(expr: &str, low: i64, high: i64) -> Result<Vec<bool>, &'static str> {
    if expr.is_empty() {
        return Err("empty field");
    }
    let mut set = vec![false; (high + 1) as usize];
    for part in expr.split(',') {
        if part.is_empty() {
            return Err("empty list item");
        }
        let (range, step) = match part.split_once('/') {
            Some((range, step)) => {
                let step = step.parse::<i64>().map_err(|_| "bad step")?;
                (range, step)
            }
            None => (part, 1),
        };
        if step <= 0 {
            return Err("bad step");
        }
        let (start, end) = if range == "*" {
            (low, high)
        } else if let Some((a, b)) = range.split_once('-') {
            let a = a.parse::<i64>().map_err(|_| "bad number")?;
            let b = b.parse::<i64>().map_err(|_| "bad number")?;
            (a, b)
        } else {
            let value = range.parse::<i64>().map_err(|_| "bad number")?;
            (value, value)
        };
        if start < low || end > high || start > end {
            return Err("out of range");
        }
        let mut value = start;
        while value <= end {
            set[value as usize] = true;
            value += step;
        }
    }
    Ok(set)
}

impl Cron {
    /// Parses `minute hour day-of-month month day-of-week`.
    pub fn parse(expr: &str) -> Result<Cron, &'static str> {
        let fields: Vec<&str> = expr.split_whitespace().collect();
        if fields.len() != 5 {
            return Err("expected 5 fields");
        }
        let minutes = parse_field(fields[0], 0, 59)?;
        let hours = parse_field(fields[1], 0, 23)?;
        let days_of_month = parse_field(fields[2], 1, 31)?;
        let months = parse_field(fields[3], 1, 12)?;
        // Day-of-week accepts 7 as Sunday; fold it into 0.
        let raw_dow = parse_field(fields[4], 0, 7)?;
        let mut days_of_week = vec![false; 7];
        for (index, matched) in raw_dow.iter().enumerate().take(7) {
            days_of_week[index] = *matched;
        }
        if raw_dow[7] {
            days_of_week[0] = true;
        }
        Ok(Cron {
            minutes,
            hours,
            days_of_month,
            months,
            days_of_week,
        })
    }

    /// Whether `civil` matches every field.
    pub fn matches(&self, civil: &Civil) -> bool {
        self.minutes[civil.minute as usize]
            && self.hours[civil.hour as usize]
            && self.days_of_month[civil.day as usize]
            && self.months[civil.month as usize]
            && self.days_of_week[civil.weekday as usize]
    }

    /// The first occurrence strictly after `from_ms`, or `None` within the bounded search.
    pub fn next_after(&self, from_ms: i64) -> Option<i64> {
        let mut moment = from_ms.div_euclid(MINUTE_MS) * MINUTE_MS + MINUTE_MS;
        for _ in 0..MAX_SEARCH_MINUTES {
            if self.matches(&civil::split(moment)) {
                return Some(moment);
            }
            moment += MINUTE_MS;
        }
        None
    }

    /// The most recent occurrence at or before `now_ms`, or `None` within the bounded search.
    pub fn latest_at_or_before(&self, now_ms: i64) -> Option<i64> {
        let mut moment = now_ms.div_euclid(MINUTE_MS) * MINUTE_MS;
        for _ in 0..MAX_SEARCH_MINUTES {
            if self.matches(&civil::split(moment)) {
                return Some(moment);
            }
            moment -= MINUTE_MS;
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn civil_at(year: i64, month: i64, day: i64, hour: i64, minute: i64) -> Civil {
        civil::split(civil::epoch_ms(
            civil::days_from_civil(year, month, day),
            hour * 60 + minute,
        ))
    }

    #[test]
    fn parses_ranges_steps_and_lists() {
        let cron = Cron::parse("*/15 9-17 * * 1-5").expect("valid");
        assert!(cron.matches(&civil_at(2024, 1, 1, 9, 0)));
        assert!(cron.matches(&civil_at(2024, 1, 1, 17, 45)));
        assert!(!cron.matches(&civil_at(2024, 1, 1, 17, 50)));
        assert!(!cron.matches(&civil_at(2024, 1, 1, 8, 0)));
        // 2024-01-06 is a Saturday.
        assert!(!cron.matches(&civil_at(2024, 1, 6, 9, 0)));

        let listy = Cron::parse("0,30 8,20 1,15 * *").expect("valid");
        assert!(listy.matches(&civil_at(2024, 3, 15, 20, 30)));
        assert!(!listy.matches(&civil_at(2024, 3, 14, 20, 30)));

        // Sunday may be written 0 or 7.
        assert!(Cron::parse("0 0 * * 7")
            .unwrap()
            .matches(&civil_at(2024, 1, 7, 0, 0)));
        assert!(Cron::parse("0 0 * * 0")
            .unwrap()
            .matches(&civil_at(2024, 1, 7, 0, 0)));
    }

    #[test]
    fn rejects_malformed_expressions() {
        assert!(Cron::parse("* * * *").is_err());
        assert!(Cron::parse("60 * * * *").is_err());
        assert!(Cron::parse("* 24 * * *").is_err());
        assert!(Cron::parse("*/0 * * * *").is_err());
        assert!(Cron::parse("a * * * *").is_err());
    }

    #[test]
    fn next_and_latest_occurrences_cross_midnight_and_month() {
        let cron = Cron::parse("30 23 * * *").expect("valid");
        // 23:45 → the next 23:30 is tomorrow.
        let from = civil::epoch_ms(civil::days_from_civil(2024, 1, 31), 23 * 60 + 45);
        let next = cron.next_after(from).expect("next");
        let civil_next = civil::split(next);
        assert_eq!(
            (
                civil_next.month,
                civil_next.day,
                civil_next.hour,
                civil_next.minute
            ),
            (2, 1, 23, 30)
        );
        // Latest at 23:45 is today 23:30.
        let latest = cron.latest_at_or_before(from).expect("latest");
        assert_eq!(civil::split(latest).day, 31);
    }
}
