//! Go-compatible `time.Duration` JSON representation.
//!
//! Go serializes `time.Duration` as an integer number of nanoseconds and a handful of config
//! structs additionally accept a duration string such as `"5s"` or `"168h"` on input. The
//! [`DurationValue`] newtype reproduces both sides of that contract:
//!
//! * deserialize from a Go duration string **or** an integer number of nanoseconds;
//! * serialize as an integer number of nanoseconds.
//!
//! The parser mirrors `time.ParseDuration` closely enough for configuration files: signed
//! sequences of decimal numbers with `ns`, `us`, `µs`, `μs`, `ms`, `s`, `m` and `h` units,
//! including fractions (`"1.5h"`) and compounds (`"1h30m"`). Bare numbers other than `"0"`
//! are rejected, exactly like Go.

use std::fmt;

use serde::de::{self, Visitor};
use serde::{Deserialize, Deserializer, Serialize, Serializer};

/// A duration expressed as nanoseconds, matching Go's `time.Duration` JSON form.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct DurationValue(pub i64);

impl DurationValue {
    /// Zero duration.
    pub const ZERO: Self = Self(0);

    /// Build a duration from a nanosecond count.
    pub const fn from_nanos(nanos: i64) -> Self {
        Self(nanos)
    }

    /// Build a duration from a whole number of seconds.
    pub const fn from_secs(seconds: i64) -> Self {
        Self(seconds * 1_000_000_000)
    }

    /// Build a duration from a whole number of milliseconds.
    pub const fn from_millis(millis: i64) -> Self {
        Self(millis * 1_000_000)
    }

    /// Build a duration from a whole number of hours.
    pub const fn from_hours(hours: i64) -> Self {
        Self(hours * 3_600 * 1_000_000_000)
    }

    /// Nanoseconds as stored on the wire.
    pub const fn as_nanos(self) -> i64 {
        self.0
    }

    /// Whole seconds (truncating), for callers that need a human-facing value.
    pub const fn as_secs(self) -> i64 {
        self.0 / 1_000_000_000
    }
}

impl From<i64> for DurationValue {
    fn from(value: i64) -> Self {
        Self(value)
    }
}

impl Serialize for DurationValue {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_i64(self.0)
    }
}

impl<'de> Deserialize<'de> for DurationValue {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        deserializer.deserialize_any(DurationVisitor)
    }
}

/// Deserialize a duration field, treating JSON `null` as the supplied default.
///
/// Serde's container-level defaults only cover *missing* fields; Go's custom unmarshallers leave
/// the pre-populated default untouched when the key is present but `null`.
pub fn deserialize_or_default<'de, D>(
    deserializer: D,
    default: DurationValue,
) -> Result<DurationValue, D::Error>
where
    D: Deserializer<'de>,
{
    Ok(Option::<DurationValue>::deserialize(deserializer)?.unwrap_or(default))
}

struct DurationVisitor;

impl<'de> Visitor<'de> for DurationVisitor {
    type Value = DurationValue;

    fn expecting(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str("a Go duration string or an integer number of nanoseconds")
    }

    fn visit_str<E>(self, value: &str) -> Result<Self::Value, E>
    where
        E: de::Error,
    {
        parse_go_duration(value)
            .map(DurationValue)
            .map_err(|error| E::custom(error.to_string()))
    }

    fn visit_string<E>(self, value: String) -> Result<Self::Value, E>
    where
        E: de::Error,
    {
        self.visit_str(&value)
    }

    fn visit_i64<E>(self, value: i64) -> Result<Self::Value, E>
    where
        E: de::Error,
    {
        Ok(DurationValue(value))
    }

    fn visit_u64<E>(self, value: u64) -> Result<Self::Value, E>
    where
        E: de::Error,
    {
        i64::try_from(value)
            .map(DurationValue)
            .map_err(|_| E::custom("duration nanoseconds exceed i64"))
    }

    fn visit_f64<E>(self, value: f64) -> Result<Self::Value, E>
    where
        E: de::Error,
    {
        if !value.is_finite() {
            return Err(E::custom("duration must be finite"));
        }
        // Go converts float64 nanoseconds directly with time.Duration(val).
        Ok(DurationValue(value as i64))
    }

    fn visit_unit<E>(self) -> Result<Self::Value, E>
    where
        E: de::Error,
    {
        Ok(DurationValue::ZERO)
    }

    fn visit_none<E>(self) -> Result<Self::Value, E>
    where
        E: de::Error,
    {
        Ok(DurationValue::ZERO)
    }

    fn visit_some<D>(self, deserializer: D) -> Result<Self::Value, D::Error>
    where
        D: Deserializer<'de>,
    {
        DurationValue::deserialize(deserializer)
    }
}

/// Error returned when a string is not a valid Go duration.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DurationParseError {
    message: String,
}

impl fmt::Display for DurationParseError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for DurationParseError {}

fn invalid(original: &str) -> DurationParseError {
    DurationParseError {
        message: format!("invalid duration {original:?}"),
    }
}

/// Parse a Go `time.ParseDuration` compatible string into nanoseconds.
pub fn parse_go_duration(input: &str) -> Result<i64, DurationParseError> {
    let original = input;
    let mut text = input;
    let mut negative = false;

    if let Some(rest) = text.strip_prefix('+') {
        text = rest;
    } else if let Some(rest) = text.strip_prefix('-') {
        negative = true;
        text = rest;
    }

    if text == "0" {
        return Ok(0);
    }
    if text.is_empty() {
        return Err(invalid(original));
    }

    let mut total: i128 = 0;
    while !text.is_empty() {
        let (component, rest) = parse_component(text).ok_or_else(|| invalid(original))?;
        total = total
            .checked_add(component)
            .ok_or_else(|| invalid(original))?;
        text = rest;
    }

    let signed = if negative { -total } else { total };
    if signed < i128::from(i64::MIN) || signed > i128::from(i64::MAX) {
        return Err(invalid(original));
    }
    Ok(signed as i64)
}

/// Parse one `<number><unit>` component, returning nanoseconds and the remaining input.
fn parse_component(text: &str) -> Option<(i128, &str)> {
    let bytes = text.as_bytes();
    let mut index = 0;
    let mut integer: i128 = 0;
    let mut has_integer = false;

    while index < bytes.len() && bytes[index].is_ascii_digit() {
        integer = integer.checked_mul(10)?;
        integer = integer.checked_add(i128::from(bytes[index] - b'0'))?;
        has_integer = true;
        index += 1;
    }

    let mut fraction: i128 = 0;
    let mut scale: i128 = 1;
    let mut has_fraction = false;
    if index < bytes.len() && bytes[index] == b'.' {
        index += 1;
        while index < bytes.len() && bytes[index].is_ascii_digit() {
            // Go stops accumulating fraction digits once the scale would overflow; extra digits
            // merely lose precision rather than rejecting the value.
            if scale <= 1_000_000_000_000_000_000 {
                fraction = fraction
                    .checked_mul(10)?
                    .checked_add(i128::from(bytes[index] - b'0'))?;
                scale *= 10;
            }
            has_fraction = true;
            index += 1;
        }
    }

    if !has_integer && !has_fraction {
        return None;
    }

    let (unit, unit_len) = match_unit(&text[index..])?;
    let integer_nanos = integer.checked_mul(unit)?;
    let fraction_nanos = fraction.checked_mul(unit)?.checked_div(scale)?;
    let nanos = integer_nanos.checked_add(fraction_nanos)?;
    Some((nanos, &text[index + unit_len..]))
}

/// Match the longest supported unit prefix and return its nanosecond multiplier.
fn match_unit(text: &str) -> Option<(i128, usize)> {
    // Longest first so `ms` wins over `m`, and `µs`/`μs` (multi-byte) win over `s`.
    const UNITS: [(&str, i128); 8] = [
        ("ns", 1),
        ("us", 1_000),
        ("µs", 1_000), // U+00B5 MICRO SIGN
        ("μs", 1_000), // U+03BC GREEK SMALL LETTER MU
        ("ms", 1_000_000),
        ("s", 1_000_000_000),
        ("m", 60 * 1_000_000_000),
        ("h", 3_600 * 1_000_000_000),
    ];
    UNITS
        .iter()
        .find(|(unit, _)| text.starts_with(unit))
        .map(|(unit, multiplier)| (*multiplier, unit.len()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_go_duration_strings() {
        assert_eq!(parse_go_duration("0"), Ok(0));
        assert_eq!(parse_go_duration("5s"), Ok(5_000_000_000));
        assert_eq!(parse_go_duration("168h"), Ok(604_800_000_000_000));
        assert_eq!(parse_go_duration("1.5h"), Ok(5_400_000_000_000));
        assert_eq!(parse_go_duration(".5s"), Ok(500_000_000));
        assert_eq!(parse_go_duration("1h30m"), Ok(5_400_000_000_000));
        assert_eq!(parse_go_duration("-2m"), Ok(-120_000_000_000));
        assert_eq!(parse_go_duration("+1ms"), Ok(1_000_000));
        assert_eq!(parse_go_duration("250us"), Ok(250_000));
        assert_eq!(parse_go_duration("250µs"), Ok(250_000));
        assert_eq!(parse_go_duration("250μs"), Ok(250_000));
    }

    #[test]
    fn rejects_invalid_durations() {
        assert!(parse_go_duration("").is_err());
        assert!(parse_go_duration("5").is_err());
        assert!(parse_go_duration("1d").is_err());
        assert!(parse_go_duration("2s-1s").is_err());
        assert!(parse_go_duration("s").is_err());
    }

    #[test]
    fn deserializes_strings_and_numbers() {
        let string: DurationValue = serde_json::from_str("\"5s\"").unwrap();
        assert_eq!(string, DurationValue::from_secs(5));

        let number: DurationValue = serde_json::from_str("5000000000").unwrap();
        assert_eq!(number, DurationValue::from_secs(5));

        let float: DurationValue = serde_json::from_str("1500000000.0").unwrap();
        assert_eq!(float, DurationValue::from_nanos(1_500_000_000));

        assert!(serde_json::from_str::<DurationValue>("\"oops\"").is_err());
    }

    #[test]
    fn serializes_as_nanoseconds() {
        let encoded = serde_json::to_string(&DurationValue::from_secs(7)).unwrap();
        assert_eq!(encoded, "7000000000");
    }

    #[test]
    fn null_uses_supplied_default() {
        fn de<'de, D>(deserializer: D) -> Result<DurationValue, D::Error>
        where
            D: Deserializer<'de>,
        {
            deserialize_or_default(deserializer, DurationValue::from_secs(9))
        }

        #[derive(Deserialize)]
        struct Wrapper {
            #[serde(deserialize_with = "de")]
            value: DurationValue,
        }

        let from_null: Wrapper = serde_json::from_str(r#"{"value": null}"#).unwrap();
        assert_eq!(from_null.value, DurationValue::from_secs(9));
    }
}
