use std::sync::RwLock;

pub const DEFAULT_EWMA_NS: i64 = 50_000_000;
pub const EWMA_ALPHA: f64 = 0.3;
pub const RTT_VAR_BETA: f64 = 0.25;
pub const FAIL_RATE_ALPHA: f64 = 0.2;
pub const FAIL_RATE_COST_NS: i64 = 1_000_000_000;
pub const FAILURE_PENALTY_STEP_NS: i64 = 100_000_000;
pub const FAILURE_PENALTY_MAX_NS: i64 = 5_000_000_000;
pub const FAILURE_PENALTY_HALF_LIFE_NS: f64 = 30_000_000_000.0;
pub const HEDGE_DELAY_COLD_NS: i64 = 50_000_000;
pub const HEDGE_DELAY_MIN_NS: i64 = 20_000_000;
pub const HEDGE_DELAY_MAX_NS: i64 = 800_000_000;
pub const HEDGE_VAR_FACTOR: i64 = 2;
pub const ATTEMPT_TIMEOUT_COLD_NS: i64 = 1_500_000_000;
pub const ATTEMPT_TIMEOUT_MIN_NS: i64 = 300_000_000;
pub const ATTEMPT_TIMEOUT_MAX_NS: i64 = 2_000_000_000;
pub const ATTEMPT_VAR_FACTOR: i64 = 4;
pub const UDP_RETRY_DELAY_COLD_NS: i64 = 400_000_000;
pub const UDP_RETRY_DELAY_MIN_NS: i64 = 200_000_000;
pub const UDP_RETRY_DELAY_MAX_NS: i64 = 1_500_000_000;
pub const UDP_RETRY_VAR_FACTOR: i64 = 4;
pub const CIRCUIT_TRIP_THRESHOLD: u32 = 3;
pub const CIRCUIT_BASE_COOLDOWN_NS: i64 = 5_000_000_000;
pub const CIRCUIT_MAX_COOLDOWN_NS: i64 = 60_000_000_000;
pub const CIRCUIT_MAX_SHIFT: u32 = 6;
pub const PROBE_CLAIM_STALE_NS: i64 = 10_000_000_000;

#[derive(Debug, Clone, Copy, PartialEq)]
struct State {
    ewma_rtt_ns: i64,
    rtt_var_ns: i64,
    fail_rate: f64,
    failure_count: u32,
    last_failure_ns: i64,
    last_success_ns: i64,
    sample_count: i64,
    circuit_open_until_ns: i64,
    probe_in_flight: bool,
    probe_claimed_ns: i64,
}

impl State {
    fn cold() -> Self {
        Self {
            ewma_rtt_ns: DEFAULT_EWMA_NS,
            rtt_var_ns: 0,
            fail_rate: 0.0,
            failure_count: 0,
            last_failure_ns: 0,
            last_success_ns: 0,
            sample_count: 0,
            circuit_open_until_ns: 0,
            probe_in_flight: false,
            probe_claimed_ns: 0,
        }
    }

    fn observe_rtt(&mut self, rtt_ns: i64) {
        if self.sample_count == 0 {
            self.ewma_rtt_ns = rtt_ns;
            self.rtt_var_ns = rtt_ns / 2;
        } else {
            let dev = (rtt_ns - self.ewma_rtt_ns).abs();
            self.rtt_var_ns =
                ((1.0 - RTT_VAR_BETA) * self.rtt_var_ns as f64 + RTT_VAR_BETA * dev as f64) as i64;
            self.ewma_rtt_ns =
                ((1.0 - EWMA_ALPHA) * self.ewma_rtt_ns as f64 + EWMA_ALPHA * rtt_ns as f64) as i64;
        }
        self.sample_count += 1;
    }

    fn score_at(&self, now_ns: i64) -> i64 {
        let mut score = self
            .ewma_rtt_ns
            .saturating_add((self.fail_rate * FAIL_RATE_COST_NS as f64) as i64);
        if self.failure_count > 0 {
            let mut penalty = self.failure_count as i64 * FAILURE_PENALTY_STEP_NS;
            if penalty > FAILURE_PENALTY_MAX_NS {
                penalty = FAILURE_PENALTY_MAX_NS;
            }
            if self.last_failure_ns != 0 {
                let since = now_ns - self.last_failure_ns;
                if since > 0 {
                    let decay = (-(since as f64) / FAILURE_PENALTY_HALF_LIFE_NS).exp2();
                    penalty = (penalty as f64 * decay) as i64;
                }
            }
            score = score.saturating_add(penalty);
        }
        score
    }

    fn tail_latency(&self, cold_ns: i64, factor: i64, min_ns: i64, max_ns: i64) -> i64 {
        if self.sample_count == 0 {
            return cold_ns;
        }
        let d = self
            .ewma_rtt_ns
            .saturating_add(factor.saturating_mul(self.rtt_var_ns));
        d.clamp(min_ns, max_ns)
    }
}

pub struct ProviderStats {
    state: RwLock<State>,
}

impl Default for ProviderStats {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Snapshot {
    pub ewma_rtt_ns: i64,
    pub rtt_var_ns: i64,
    pub fail_rate: f64,
    pub failure_count: u32,
    pub last_failure_ns: i64,
    pub last_success_ns: i64,
    pub sample_count: i64,
    pub circuit_open_until_ns: i64,
    pub probe_in_flight: bool,
}

impl ProviderStats {
    pub fn new() -> Self {
        Self {
            state: RwLock::new(State::cold()),
        }
    }

    pub fn reset(&self) {
        *self.write() = State::cold();
    }

    pub fn record_success(&self, rtt_ns: i64, now_ns: i64) {
        let mut state = self.write();
        state.last_success_ns = now_ns;
        state.failure_count = 0;
        state.circuit_open_until_ns = 0;
        state.probe_in_flight = false;
        state.fail_rate *= 1.0 - FAIL_RATE_ALPHA;
        state.observe_rtt(rtt_ns);
    }

    pub fn record_failure(&self, now_ns: i64) {
        self.record_failure_weight(1, now_ns);
    }

    pub fn record_policy_failure(&self, now_ns: i64) {
        self.record_failure_weight(CIRCUIT_TRIP_THRESHOLD, now_ns);
    }

    pub fn record_failure_weight(&self, weight: u32, now_ns: i64) {
        let weight = weight.max(1);
        let mut state = self.write();
        state.last_failure_ns = now_ns;
        state.failure_count = state.failure_count.saturating_add(weight);
        state.probe_in_flight = false;
        for _ in 0..weight {
            state.fail_rate = (1.0 - FAIL_RATE_ALPHA) * state.fail_rate + FAIL_RATE_ALPHA;
        }
        if state.failure_count >= CIRCUIT_TRIP_THRESHOLD {
            let shift = (state.failure_count - CIRCUIT_TRIP_THRESHOLD).min(CIRCUIT_MAX_SHIFT);
            let cooldown = (CIRCUIT_BASE_COOLDOWN_NS << shift).min(CIRCUIT_MAX_COOLDOWN_NS);
            state.circuit_open_until_ns = now_ns.saturating_add(cooldown);
        }
    }

    pub fn allow_attempt(&self, now_ns: i64) -> bool {
        let mut state = self.write();
        if state.circuit_open_until_ns == 0 {
            return true;
        }
        if now_ns < state.circuit_open_until_ns {
            return false;
        }
        if state.probe_in_flight
            && now_ns.saturating_sub(state.probe_claimed_ns) < PROBE_CLAIM_STALE_NS
        {
            return false;
        }
        state.probe_in_flight = true;
        state.probe_claimed_ns = now_ns;
        true
    }

    pub fn record_censored(&self, elapsed_ns: i64) {
        let mut state = self.write();
        state.probe_in_flight = false;
        if state.sample_count > 0 && elapsed_ns <= state.ewma_rtt_ns {
            return;
        }
        if state.sample_count == 0 && elapsed_ns <= DEFAULT_EWMA_NS {
            return;
        }
        state.observe_rtt(elapsed_ns);
    }

    pub fn score(&self, now_ns: i64) -> i64 {
        self.read().score_at(now_ns)
    }

    pub fn hedge_delay(&self) -> i64 {
        self.read().tail_latency(
            HEDGE_DELAY_COLD_NS,
            HEDGE_VAR_FACTOR,
            HEDGE_DELAY_MIN_NS,
            HEDGE_DELAY_MAX_NS,
        )
    }

    pub fn attempt_timeout(&self) -> i64 {
        self.read().tail_latency(
            ATTEMPT_TIMEOUT_COLD_NS,
            ATTEMPT_VAR_FACTOR,
            ATTEMPT_TIMEOUT_MIN_NS,
            ATTEMPT_TIMEOUT_MAX_NS,
        )
    }

    pub fn udp_retry_delay(&self) -> i64 {
        self.read().tail_latency(
            UDP_RETRY_DELAY_COLD_NS,
            UDP_RETRY_VAR_FACTOR,
            UDP_RETRY_DELAY_MIN_NS,
            UDP_RETRY_DELAY_MAX_NS,
        )
    }

    pub fn snapshot(&self) -> Snapshot {
        let state = self.read();
        Snapshot {
            ewma_rtt_ns: state.ewma_rtt_ns,
            rtt_var_ns: state.rtt_var_ns,
            fail_rate: state.fail_rate,
            failure_count: state.failure_count,
            last_failure_ns: state.last_failure_ns,
            last_success_ns: state.last_success_ns,
            sample_count: state.sample_count,
            circuit_open_until_ns: state.circuit_open_until_ns,
            probe_in_flight: state.probe_in_flight,
        }
    }

    pub fn sample_count(&self) -> i64 {
        self.read().sample_count
    }

    pub fn failure_count(&self) -> u32 {
        self.read().failure_count
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, State> {
        self.state.read().unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, State> {
        self.state
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

#[cfg(test)]
mod tests;
