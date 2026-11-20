pub const DEFAULT_LATENCY_MS: f64 = 250.0;
pub const MIN_LATENCY_MS: f64 = 20.0;
pub const MAX_LATENCY_MS: f64 = 5000.0;
pub const MIN_WEIGHT: f64 = 0.05;
pub const MAX_WEIGHT: f64 = 3.0;
pub const JITTER_WEIGHT: f64 = 0.5;
pub const COOLDOWN_PENALTY: f64 = 0.1;
pub const CONSECUTIVE_FAIL_PENALTY: f64 = 0.2;
pub const EWMA_ALPHA: f64 = 0.25;
pub const JITTER_ALPHA: f64 = 0.20;
pub const BASE_EXPLORATION_RATE: f64 = 0.02;
pub const LOW_SAMPLE_EXPLORATION_RATE: f64 = 0.08;
pub const RECOVERY_EXPLORATION_RATE: f64 = 0.10;
pub const LOW_SAMPLE_THRESHOLD: f64 = 10.0;
pub const COOLDOWN_FAILURE_THRESHOLD: u32 = 3;
pub const COOLDOWN_DURATION_NS: i64 = 30_000_000_000;
pub const HEALTH_HALF_LIFE_NS: f64 = 1_800_000_000_000.0;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Score {
    pub weight: f64,
    pub cooling_down: bool,
    pub sample_count: f64,
}

#[derive(Debug, Clone)]
pub struct Health {
    successes: u64,
    failures: u64,
    ewma_ms: f64,
    jitter_ms: f64,
    consecutive_failures: u32,
    cooldown_until_ns: i64,
    decayed_successes: f64,
    decayed_failures: f64,
    last_updated_ns: i64,
}

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
