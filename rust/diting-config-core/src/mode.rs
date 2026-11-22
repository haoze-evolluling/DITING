use diting_go_compat::text::go_lower_trim;

use crate::quote::go_quote;

pub const MODE_SINGLE: &str = "single";
pub const MODE_PRIMARY_BACKUP: &str = "primary_backup";
pub const MODE_PARALLEL_RACE: &str = "parallel_race";
pub const MODE_SMART_PREDICTION: &str = "smart_prediction";

pub fn canonical_dns_mode(mode: &str) -> Result<&'static str, String> {
    let lowered = go_lower_trim(mode);
    match lowered.as_str() {
        "single" => Ok(MODE_SINGLE),
        "primary_backup" => Ok(MODE_PRIMARY_BACKUP),
        "parallel_race" | "race" | "brute_force_parallel" => Ok(MODE_PARALLEL_RACE),
        "smart_prediction" | "prediction" => Ok(MODE_SMART_PREDICTION),
        _ => Err(format!("unsupported DNS mode {}", go_quote(mode))),
    }
}

#[cfg(test)]
mod tests;
