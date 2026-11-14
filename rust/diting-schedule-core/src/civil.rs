//! Timezone-free civil calendar arithmetic.
//!
//! The kernel never reads a clock or a timezone: `now` and every wall-clock slot are passed in as
//! "local civil milliseconds" — the local calendar encoded as if it were UTC. The platform layer
//! (Dart `DateTime`, Kotlin `Calendar`) owns the real UTC↔local mapping, so a DST transition is a
//! slot table the caller builds, not arithmetic here. This module turns those milliseconds into
//! `year/month/day/hour/minute/weekday` and back.

/// Milliseconds in a day, for the fixed civil grid (DST is the caller's concern).
pub const DAY_MS: i64 = 86_400_000;
/// Milliseconds in a minute; every cron occurrence lands on a minute boundary.
pub const MINUTE_MS: i64 = 60_000;

/// One instant split into civil fields; `weekday` is 0 = Sunday .. 6 = Saturday.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Civil {
    pub days: i64,
    pub year: i64,
    pub month: i64,
    pub day: i64,
    pub hour: i64,
    pub minute: i64,
    pub weekday: i64,
    pub minute_of_day: i64,
}

/// Days since 1970-01-01 → `(year, month, day)`; Howard Hinnant's `civil_from_days`.
pub fn civil_from_days(days: i64) -> (i64, i64, i64) {
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = z - era * 146_097;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let year = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    (if month <= 2 { year + 1 } else { year }, month, day)
}

/// `(year, month, day)` → days since 1970-01-01; inverse of [`civil_from_days`].
pub fn days_from_civil(year: i64, month: i64, day: i64) -> i64 {
    let year = if month <= 2 { year - 1 } else { year };
    let era = if year >= 0 { year } else { year - 399 } / 400;
    let yoe = year - era * 400;
    let doy = (153 * (if month > 2 { month - 3 } else { month + 9 }) + 2) / 5 + day - 1;
    let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
    era * 146_097 + doe - 719_468
}

/// Splits civil milliseconds into fields.
pub fn split(ms: i64) -> Civil {
    let days = ms.div_euclid(DAY_MS);
    let minute_of_day = ms.rem_euclid(DAY_MS) / MINUTE_MS;
    let (year, month, day) = civil_from_days(days);
    // 1970-01-01 was a Thursday (4 with Sunday = 0).
    let weekday = (days + 4).rem_euclid(7);
    Civil {
        days,
        year,
        month,
        day,
        hour: minute_of_day / 60,
        minute: minute_of_day % 60,
        weekday,
        minute_of_day,
    }
}

/// Civil milliseconds for `days` at `minute_of_day`.
pub fn epoch_ms(days: i64, minute_of_day: i64) -> i64 {
    days * DAY_MS + minute_of_day * MINUTE_MS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trips_epoch_and_leap_days() {
        // 1970-01-01 is day 0, a Thursday.
        assert_eq!(civil_from_days(0), (1970, 1, 1));
        assert_eq!(days_from_civil(1970, 1, 1), 0);
        // 2024-02-29 (leap day) round trips.
        let days = days_from_civil(2024, 2, 29);
        assert_eq!(civil_from_days(days), (2024, 2, 29));
        // A pre-epoch date still round trips.
        let days = days_from_civil(1965, 7, 4);
        assert_eq!(civil_from_days(days), (1965, 7, 4));
    }

    #[test]
    fn split_reports_weekday_and_minute_of_day() {
        let ms = epoch_ms(days_from_civil(2024, 1, 1), 23 * 60 + 30);
        let civil = split(ms);
        assert_eq!((civil.year, civil.month, civil.day), (2024, 1, 1));
        assert_eq!((civil.hour, civil.minute), (23, 30));
        // 2024-01-01 was a Monday (1 with Sunday = 0).
        assert_eq!(civil.weekday, 1);
        assert_eq!(civil.minute_of_day, 23 * 60 + 30);
    }
}
