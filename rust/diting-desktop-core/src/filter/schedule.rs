//! Weekly blocking windows (`BlockingSchedule`) ported from Go's `schedule.go`.
//!
//! The API model is only the textual form (`weekdays`, `start`, `end`); this module compiles it to
//! "weekday bitmask + two minute offsets" once per configuration update and evaluates it without
//! allocating. `start == end` is a zero-length window and never active; `start > end` is an
//! overnight window whose weekday belongs to the day it starts on.

use chrono::{DateTime, Datelike, Local, Timelike, Weekday};
use diting_desktop_api::config::BlockingSchedule;

const ALL_WEEKDAYS: u8 = 0x7F;
const WEEKDAY_KEYS: [&str; 7] = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"];

/// One compiled weekly window.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct CompiledSchedule {
    pub(crate) id: String,
    pub(crate) name: String,
    pub(crate) enabled: bool,
    start_min: i32,
    end_min: i32,
    weekday_mask: u8,
}

impl CompiledSchedule {
    /// `NormalizeSchedule`: validates `HH:MM` clocks and weekday keys.
    pub(crate) fn compile(raw: &BlockingSchedule) -> Result<Self, String> {
        let start_min = parse_clock(&raw.start)?;
        let end_min = parse_clock(&raw.end)?;
        let weekday_mask = parse_weekdays(&raw.weekdays)?;
        Ok(Self {
            id: raw.id.trim().to_string(),
            name: raw.name.trim().to_string(),
            enabled: raw.enabled,
            start_min,
            end_min,
            weekday_mask,
        })
    }

    /// `BlockingSchedule.IsActive`.
    pub(crate) fn is_active(&self, now: &DateTime<Local>) -> bool {
        if !self.enabled || self.weekday_mask == 0 {
            return false;
        }
        // A zero-length window is valid configuration but never active.
        if self.start_min == self.end_min {
            return false;
        }

        let now_min = now.hour() as i32 * 60 + now.minute() as i32;
        let today = weekday_bit(now.weekday());

        if self.start_min < self.end_min {
            // Same-day window [start, end).
            return now_min >= self.start_min
                && now_min < self.end_min
                && self.weekday_mask & today != 0;
        }

        // Overnight window: today's [start, 24:00) or tomorrow's [00:00, end).
        if now_min >= self.start_min {
            return self.weekday_mask & today != 0;
        }
        if now_min < self.end_min {
            let yesterday = weekday_bit(previous_weekday(now.weekday()));
            return self.weekday_mask & yesterday != 0;
        }
        false
    }
}

/// Compiles every entry, dropping invalid ones (Go's normalization does the same).
pub(crate) fn compile_all(schedules: &[BlockingSchedule]) -> Vec<CompiledSchedule> {
    schedules
        .iter()
        .filter_map(|schedule| CompiledSchedule::compile(schedule).ok())
        .collect()
}

/// `HasEnabledSchedule`.
pub(crate) fn has_enabled(schedules: &[CompiledSchedule]) -> bool {
    schedules.iter().any(|schedule| schedule.enabled)
}

/// `ActiveSchedule`.
pub(crate) fn any_active(schedules: &[CompiledSchedule], now: &DateTime<Local>) -> bool {
    schedules.iter().any(|schedule| schedule.is_active(now))
}

/// `FirstActiveSchedule`.
pub(crate) fn first_active<'a>(
    schedules: &'a [CompiledSchedule],
    now: &DateTime<Local>,
) -> Option<&'a CompiledSchedule> {
    schedules.iter().find(|schedule| schedule.is_active(now))
}

fn parse_clock(raw: &str) -> Result<i32, String> {
    let value = raw.trim();
    if value.is_empty() {
        return Err("时刻不能为空".to_string());
    }
    let parts: Vec<&str> = value.split(':').collect();
    if parts.len() != 2 {
        return Err(format!("时刻格式应为 HH:MM，得到 {raw:?}"));
    }
    let hour: i32 = parts[0]
        .trim()
        .parse()
        .map_err(|_| format!("小时非法: {raw:?}"))?;
    let minute: i32 = parts[1]
        .trim()
        .parse()
        .map_err(|_| format!("分钟非法: {raw:?}"))?;
    if !(0..=23).contains(&hour) {
        return Err(format!("小时非法: {raw:?}"));
    }
    if !(0..=59).contains(&minute) {
        return Err(format!("分钟非法: {raw:?}"));
    }
    Ok(hour * 60 + minute)
}

fn parse_weekdays(days: &[String]) -> Result<u8, String> {
    if days.is_empty() {
        return Ok(ALL_WEEKDAYS);
    }
    let mut mask = 0u8;
    for raw in days {
        let lower = raw.trim().to_lowercase();
        let key: String = lower.chars().take(3).collect();
        let index = WEEKDAY_KEYS
            .iter()
            .position(|candidate| *candidate == key)
            .ok_or_else(|| format!("星期非法: {raw:?}"))?;
        mask |= 1 << index;
    }
    Ok(mask)
}

/// `time.Weekday` bit position: Sunday is 0, Saturday is 6.
fn weekday_bit(weekday: Weekday) -> u8 {
    1 << weekday.num_days_from_sunday()
}

fn previous_weekday(weekday: Weekday) -> Weekday {
    match weekday {
        Weekday::Mon => Weekday::Sun,
        Weekday::Tue => Weekday::Mon,
        Weekday::Wed => Weekday::Tue,
        Weekday::Thu => Weekday::Wed,
        Weekday::Fri => Weekday::Thu,
        Weekday::Sat => Weekday::Fri,
        Weekday::Sun => Weekday::Sat,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn schedule(start: &str, end: &str, days: &[&str]) -> CompiledSchedule {
        let raw = BlockingSchedule {
            id: "s".into(),
            name: "s".into(),
            enabled: true,
            weekdays: days.iter().map(|day| day.to_string()).collect(),
            start: start.into(),
            end: end.into(),
        };
        CompiledSchedule::compile(&raw).expect("schedule")
    }

    #[test]
    fn same_day_window_respects_weekday() {
        let window = schedule("09:00", "17:00", &["mon"]);
        assert!(window.is_active(&local(2024, 1, 1, 10, 0))); // Monday
        assert!(!window.is_active(&local(2024, 1, 1, 8, 59)));
        assert!(!window.is_active(&local(2024, 1, 1, 17, 0)));
        assert!(!window.is_active(&local(2024, 1, 2, 10, 0))); // Tuesday
    }

    #[test]
    fn overnight_window_belongs_to_its_start_day() {
        let window = schedule("22:00", "06:00", &["mon"]);
        assert!(window.is_active(&local(2024, 1, 1, 23, 0))); // Monday evening
        assert!(window.is_active(&local(2024, 1, 2, 5, 0))); // Tuesday early
        assert!(!window.is_active(&local(2024, 1, 2, 23, 0))); // Tuesday evening
        assert!(!window.is_active(&local(2024, 1, 1, 6, 0)));
    }

    #[test]
    fn zero_length_and_disabled_windows_are_never_active() {
        assert!(!schedule("00:00", "00:00", &[]).is_active(&local(2024, 1, 1, 0, 0)));
        let mut disabled = schedule("00:00", "23:59", &[]);
        disabled.enabled = false;
        assert!(!disabled.is_active(&local(2024, 1, 1, 12, 0)));
    }

    #[test]
    fn empty_weekdays_means_every_day() {
        assert!(schedule("00:00", "23:59", &[]).is_active(&local(2024, 1, 3, 12, 0)));
    }

    #[test]
    fn invalid_clocks_and_days_are_rejected() {
        let base = BlockingSchedule {
            enabled: true,
            start: "24:00".into(),
            end: "01:00".into(),
            ..BlockingSchedule::default()
        };
        assert!(CompiledSchedule::compile(&base).is_err());
        let bad_day = BlockingSchedule {
            start: "01:00".into(),
            end: "02:00".into(),
            weekdays: vec!["funday".into()],
            ..BlockingSchedule::default()
        };
        assert!(CompiledSchedule::compile(&bad_day).is_err());
    }

    fn local(year: i32, month: u32, day: u32, hour: u32, minute: u32) -> DateTime<Local> {
        use chrono::TimeZone;
        Local
            .with_ymd_and_hms(year, month, day, hour, minute, 0)
            .single()
            .expect("local time")
    }
}
