#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strategy {
    Single,
    PrimaryBackup,
    ParallelRace,
    SmartPrediction,
}

pub fn strategy(mode: &str) -> Strategy {
    match mode {
        "single" => Strategy::Single,
        "primary_backup" => Strategy::PrimaryBackup,
        "parallel_race" | "race" => Strategy::ParallelRace,
        "smart_prediction" | "prediction" => Strategy::SmartPrediction,
        _ => Strategy::Single,
    }
}

pub fn is_policy_rejection(rcode: i32) -> bool {
    matches!(rcode, 1 | 4 | 5)
}

#[cfg(test)]
mod tests;
