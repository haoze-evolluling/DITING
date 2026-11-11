//! The provider-mode dispatch table and the rcode policy-rejection set.
//!
//! `resolveConfigured` switched on the configured mode string (with aliases), defaulting to the
//! single-upstream path; `upstreamRcodeError.isPolicyRejection` treated REFUSED, FORMERR and NOTIMP
//! as configuration rejections so the circuit breaker trips faster. Both tables are decisions, not
//! I/O, so they live here. The attempt order, budgets and timers that follow from the strategy live
//! in `diting-resolver-core`'s scheduler; the goroutines and the error texts stay in Go.

/// Which scheduling strategy a configured provider mode selects.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strategy {
    /// `"single"` and every unrecognized mode.
    Single,
    /// `"primary_backup"`.
    PrimaryBackup,
    /// `"parallel_race"` / `"race"`.
    ParallelRace,
    /// `"smart_prediction"` / `"prediction"`.
    SmartPrediction,
}

/// The mode table, aliases included.
pub fn strategy(mode: &str) -> Strategy {
    match mode {
        "single" => Strategy::Single,
        "primary_backup" => Strategy::PrimaryBackup,
        "parallel_race" | "race" => Strategy::ParallelRace,
        "smart_prediction" | "prediction" => Strategy::SmartPrediction,
        _ => Strategy::Single,
    }
}

/// `REFUSED` (5), `FORMERR` (1) and `NOTIMP` (4): the rcode values a provider treats as a policy
/// rejection rather than a transport failure.
pub fn is_policy_rejection(rcode: i32) -> bool {
    matches!(rcode, 1 | 4 | 5)
}

#[cfg(test)]
mod tests;
