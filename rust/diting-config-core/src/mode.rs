//! `canonicalDNSMode`: the four upstream scheduling modes and the spellings Android accepts.
//!
//! The canonical name is what `Resolver.ConfigureProvidersWithOptions` switches on, and the error is
//! the text the settings screen shows when a mode is not one of them.

use diting_go_compat::text::go_lower_trim;

use crate::quote::go_quote;

/// Canonical names, in the order `resolver_strategy.go` documents them.
pub const MODE_SINGLE: &str = "single";
pub const MODE_PRIMARY_BACKUP: &str = "primary_backup";
pub const MODE_PARALLEL_RACE: &str = "parallel_race";
pub const MODE_SMART_PREDICTION: &str = "smart_prediction";

/// `canonicalDNSMode`: lowercase, trim, then match the aliases.
///
/// Note what is *not* here: the comparison happens after `strings.ToLower`/`TrimSpace`, so
/// `" SINGLE "` and `"sİngle"` (Go folds `U+0130` to a plain `i`) are both `single`.
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
