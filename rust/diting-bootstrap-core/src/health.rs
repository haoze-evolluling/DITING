//! One bootstrap endpoint's health model, a field-for-field port of `bootstrapIPHealth`.
//!
//! The state machine is deliberately tiny and numeric: every field is either an exact integer or
//! an `f64` combined in the same order as the Go code, so a replay of the old implementation's
//! operation trace reproduces bit-identical values apart from the last bit of `powf` on hosts
//! whose libm rounds differently (the corpus compares with a 1e-9 tolerance).
//!
//! `cooldown_until_ns == 0` is the zero `time.Time{}` of the Go code: no cooldown was ever armed.
//! Real unix timestamps are positive, so the sentinel cannot collide with an armed deadline.

/// `bsDefaultLatencyMs`: the nominal latency, also the speed ratio's numerator.
pub const DEFAULT_LATENCY_MS: f64 = 250.0;
/// `bsMinLatencyMs`: lower clamp of the effective latency.
pub const MIN_LATENCY_MS: f64 = 20.0;
/// `bsMaxLatencyMs`: upper clamp of the effective latency.
pub const MAX_LATENCY_MS: f64 = 5000.0;
/// `bsMinWeight`: lower clamp of the score.
pub const MIN_WEIGHT: f64 = 0.05;
/// `bsMaxWeight`: upper clamp of the score.
pub const MAX_WEIGHT: f64 = 3.0;
/// `bsJitterWeight`: how much of the jitter is added to the latency.
pub const JITTER_WEIGHT: f64 = 0.5;
/// `bsCooldownPenalty`: score multiplier while cooling down.
pub const COOLDOWN_PENALTY: f64 = 0.1;
/// `bsConsecutiveFailPenalty`: per-failure multiplier of the penalty.
pub const CONSECUTIVE_FAIL_PENALTY: f64 = 0.2;
/// `bsEwmaAlpha`: weight of the newest latency sample.
pub const EWMA_ALPHA: f64 = 0.25;
/// `bsJitterAlpha`: weight of the newest deviation sample.
pub const JITTER_ALPHA: f64 = 0.20;
/// `bsBaseExplorationRate`: exploration share while every endpoint looks healthy.
pub const BASE_EXPLORATION_RATE: f64 = 0.02;
/// `bsLowSampleExplorationRate`: exploration share while some endpoint has few samples.
pub const LOW_SAMPLE_EXPLORATION_RATE: f64 = 0.08;
/// `bsRecoveryExplorationRate`: exploration share while some endpoint is cooling down.
pub const RECOVERY_EXPLORATION_RATE: f64 = 0.10;
/// `bsLowSampleThreshold`: "under-sampled" boundary (decayed attempts).
pub const LOW_SAMPLE_THRESHOLD: f64 = 10.0;
/// `bsCooldownFailureThreshold`: consecutive failures that arm the cooldown.
pub const COOLDOWN_FAILURE_THRESHOLD: u32 = 3;
/// `bsCooldownDuration`: 30 s.
pub const COOLDOWN_DURATION_NS: i64 = 30_000_000_000;
/// `bsHealthHalfLifeDuration`: 30 min.
pub const HEALTH_HALF_LIFE_NS: f64 = 1_800_000_000_000.0;

/// The result of [`Health::score`], the old `bootstrapScore` minus the config entry.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Score {
    pub weight: f64,
    pub cooling_down: bool,
    pub sample_count: f64,
}

/// One endpoint's mutable health.
#[derive(Debug, Clone)]
pub struct Health {
    /// Raw success count; only `successes > 0` is used, to decide whether a latency exists.
    successes: u64,
    /// Raw failure count (reported by the tests, not used by the score).
    failures: u64,
    ewma_ms: f64,
    jitter_ms: f64,
    consecutive_failures: u32,
    /// 0 = never armed (`time.Time{}`).
    cooldown_until_ns: i64,
    decayed_successes: f64,
    decayed_failures: f64,
    last_updated_ns: i64,
}

/// A read-only view of the whole state, for tests and the corpus replay.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Snapshot {
    pub successes: u64,
    pub failures: u64,
    pub ewma_ms: f64,
    pub jitter_ms: f64,
    pub consecutive_failures: u32,
    pub cooldown_until_ns: i64,
    pub decayed_successes: f64,
    pub decayed_failures: f64,
    pub last_updated_ns: i64,
}

impl Health {
    /// `newBootstrapIPHealth`: default latency, no attempts, no cooldown, stamped at `now_ns`.
    pub fn new(now_ns: i64) -> Self {
        Self {
            successes: 0,
            failures: 0,
            ewma_ms: DEFAULT_LATENCY_MS,
            jitter_ms: 0.0,
            consecutive_failures: 0,
            cooldown_until_ns: 0,
            decayed_successes: 0.0,
            decayed_failures: 0.0,
            last_updated_ns: now_ns,
        }
    }

    /// `applyDecayLocked`: halve the decayed counters every 30 minutes since the last touch.
    fn apply_decay(&mut self, now_ns: i64) {
        if self.last_updated_ns == 0 {
            self.last_updated_ns = now_ns;
            return;
        }
        let elapsed = now_ns - self.last_updated_ns;
        if elapsed <= 0 {
            return;
        }
        let factor = 0.5_f64.powf(elapsed as f64 / HEALTH_HALF_LIFE_NS);
        self.decayed_successes *= factor;
        self.decayed_failures *= factor;
        self.last_updated_ns = now_ns;
    }

    /// `RecordResult`: fold one attempt in. `elapsed_ms < 1` is clamped to 1, like Go does.
    pub fn record_result(&mut self, success: bool, elapsed_ms: i64, now_ns: i64) {
        self.apply_decay(now_ns);

        let mut safe_elapsed = elapsed_ms as f64;
        if safe_elapsed < 1.0 {
            safe_elapsed = 1.0;
        }

        if success {
            self.successes += 1;
            self.decayed_successes += 1.0;
            self.consecutive_failures = 0;
            self.cooldown_until_ns = 0;

            self.ewma_ms = self.ewma_ms * (1.0 - EWMA_ALPHA) + safe_elapsed * EWMA_ALPHA;
            // The deviation is taken against the *new* EWMA, exactly like the Go implementation:
            // swapping these two lines changes every jitter sample afterwards.
            self.jitter_ms = self.jitter_ms * (1.0 - JITTER_ALPHA)
                + (safe_elapsed - self.ewma_ms).abs() * JITTER_ALPHA;
        } else {
            self.failures += 1;
            self.decayed_failures += 1.0;
            self.consecutive_failures = self.consecutive_failures.saturating_add(1);
            if self.consecutive_failures >= COOLDOWN_FAILURE_THRESHOLD {
                self.cooldown_until_ns = now_ns.saturating_add(COOLDOWN_DURATION_NS);
            }
        }
        self.last_updated_ns = now_ns;
    }

    /// `GetScore`: decay to `now_ns`, then the documented weight formula.
    pub fn score(&mut self, entry_weight: f64, now_ns: i64) -> Score {
        self.apply_decay(now_ns);

        let decayed_attempts = self.decayed_successes + self.decayed_failures;
        let cooling_down = self.cooldown_until_ns != 0 && now_ns < self.cooldown_until_ns;

        if decayed_attempts <= 0.0 {
            let mut initial_weight = entry_weight;
            if initial_weight <= 0.0 {
                initial_weight = 1.0;
            }
            return Score {
                weight: initial_weight,
                cooling_down,
                sample_count: 0.0,
            };
        }

        let correctness = (self.decayed_successes + 2.0) / (decayed_attempts + 3.0);

        let mut speed = 1.0;
        if self.successes > 0 {
            let effective_latency = (self.ewma_ms + self.jitter_ms * JITTER_WEIGHT)
                .clamp(MIN_LATENCY_MS, MAX_LATENCY_MS);
            speed = DEFAULT_LATENCY_MS / effective_latency;
        }

        let cooldown_penalty = if cooling_down { COOLDOWN_PENALTY } else { 1.0 };
        let failure_penalty =
            1.0 / (1.0 + self.consecutive_failures as f64 * CONSECUTIVE_FAIL_PENALTY);

        let weight = (correctness * speed * cooldown_penalty * failure_penalty)
            .clamp(MIN_WEIGHT, MAX_WEIGHT);

        Score {
            weight,
            cooling_down,
            sample_count: decayed_attempts,
        }
    }

    /// Whole state, for the tests and the corpus replay.
    pub fn snapshot(&self) -> Snapshot {
        Snapshot {
            successes: self.successes,
            failures: self.failures,
            ewma_ms: self.ewma_ms,
            jitter_ms: self.jitter_ms,
            consecutive_failures: self.consecutive_failures,
            cooldown_until_ns: self.cooldown_until_ns,
            decayed_successes: self.decayed_successes,
            decayed_failures: self.decayed_failures,
            last_updated_ns: self.last_updated_ns,
        }
    }
}

#[cfg(test)]
mod tests;
