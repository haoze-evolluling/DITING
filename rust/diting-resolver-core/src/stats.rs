//! The per-provider health model behind the resolver's scheduling strategies.
//!
//! Field-for-field port of `providerStats` in `android/engine/resolver_stats.go` (RTO estimator
//! from TCP: SRTT + RTTVAR, EWMA failure ratio, decayed consecutive-failure penalty, exponential
//! circuit breaker). Every value is `time.Duration` nanoseconds on the Go side, so it is `i64` here;
//! `now` is unix nanoseconds.
//!
//! Conversion parity: Go writes `time.Duration((1-alpha)*float64(old) + alpha*float64(sample))`,
//! which truncates toward zero. `f64 as i64` in Rust truncates toward zero as well, and the ops are
//! performed in the same order, so the traces are bit-identical (see `tests/corpus.rs`).
//!
//! Locking: a `RwLock` over the whole state, the same shape as the Go `sync.RWMutex`. Point lookups
//! (score, hedge delay, timeouts, counters) take the read lock; the recording calls take the write
//! lock.
//!
//! Nothing here reads a clock: Go passes `time.Now()` (or the query's start time) on every call.

use std::sync::RwLock;

/// `defaultEWMA`: the score of a provider that has never been sampled.
pub const DEFAULT_EWMA_NS: i64 = 50_000_000;
/// `ewmaAlpha`: weight of the newest RTT sample in SRTT.
pub const EWMA_ALPHA: f64 = 0.3;
/// `rttVarBeta`: weight of the newest deviation in RTTVAR.
pub const RTT_VAR_BETA: f64 = 0.25;
/// `failRateAlpha`: weight of the newest observation in the failure ratio.
pub const FAIL_RATE_ALPHA: f64 = 0.2;
/// `failRateCost`: expected latency cost of a failed attempt (a 10% failure rate costs 100 ms).
pub const FAIL_RATE_COST_NS: i64 = 1_000_000_000;
/// `failurePenaltyStep`: penalty added per consecutive failure.
pub const FAILURE_PENALTY_STEP_NS: i64 = 100_000_000;
/// `failurePenaltyMax`: cap of the consecutive-failure penalty.
pub const FAILURE_PENALTY_MAX_NS: i64 = 5_000_000_000;
/// `failurePenaltyHalfLife`: the penalty halves every 30 s.
pub const FAILURE_PENALTY_HALF_LIFE_NS: f64 = 30_000_000_000.0;
/// `hedgeDelayCold`: hedge delay of a provider without samples.
pub const HEDGE_DELAY_COLD_NS: i64 = 50_000_000;
/// `hedgeDelayMin`: lower clamp of the hedge delay.
pub const HEDGE_DELAY_MIN_NS: i64 = 20_000_000;
/// `hedgeDelayMax`: upper clamp of the hedge delay.
pub const HEDGE_DELAY_MAX_NS: i64 = 800_000_000;
/// `hedgeVarFactor`: RTTVAR multiplier of the hedge delay.
pub const HEDGE_VAR_FACTOR: i64 = 2;
/// `attemptTimeoutCold`: per-attempt timeout without samples.
pub const ATTEMPT_TIMEOUT_COLD_NS: i64 = 1_500_000_000;
/// `attemptTimeoutMin`: lower clamp of the per-attempt timeout.
pub const ATTEMPT_TIMEOUT_MIN_NS: i64 = 300_000_000;
/// `attemptTimeoutMax`: upper clamp of the per-attempt timeout.
pub const ATTEMPT_TIMEOUT_MAX_NS: i64 = 2_000_000_000;
/// `attemptVarFactor`: RTTVAR multiplier of the per-attempt timeout.
pub const ATTEMPT_VAR_FACTOR: i64 = 4;
/// `udpRetryDelayCold`: plain-UDP retry interval without samples.
pub const UDP_RETRY_DELAY_COLD_NS: i64 = 400_000_000;
/// `udpRetryDelayMin`: lower clamp of the UDP retry interval.
pub const UDP_RETRY_DELAY_MIN_NS: i64 = 200_000_000;
/// `udpRetryDelayMax`: upper clamp of the UDP retry interval.
pub const UDP_RETRY_DELAY_MAX_NS: i64 = 1_500_000_000;
/// `udpRetryVarFactor`: RTTVAR multiplier of the UDP retry interval.
pub const UDP_RETRY_VAR_FACTOR: i64 = 4;
/// `circuitTripThreshold`: consecutive failures that open the circuit.
pub const CIRCUIT_TRIP_THRESHOLD: u32 = 3;
/// `circuitBaseCooldown`: cooldown after the first trip.
pub const CIRCUIT_BASE_COOLDOWN_NS: i64 = 5_000_000_000;
/// `circuitMaxCooldown`: cap of the exponential cooldown growth.
pub const CIRCUIT_MAX_COOLDOWN_NS: i64 = 60_000_000_000;
/// The cooldown doubles at most this many times (`shift > 6` is clamped to 6).
pub const CIRCUIT_MAX_SHIFT: u32 = 6;

/// The mutable part of one provider's statistics.
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
        }
    }

    /// `observeRTTLocked`: fold one RTT sample into SRTT/RTTVAR.
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

    /// `scoreAt`: SRTT + failure-ratio cost + the decayed consecutive-failure penalty.
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

/// One provider's statistics: the handle the Go resolver holds.
pub struct ProviderStats {
    state: RwLock<State>,
}

impl Default for ProviderStats {
    fn default() -> Self {
        Self::new()
    }
}

/// A read-only view of the whole state, used by the kernel tests and the corpus replay.
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
    /// A provider with no samples: `defaultEWMA`, no failure history, closed circuit.
    pub fn new() -> Self {
        Self {
            state: RwLock::new(State::cold()),
        }
    }

    /// `RecordSuccess`: clears the failure streak and the circuit, decays the failure ratio and
    /// folds `rtt_ns` into SRTT/RTTVAR.
    pub fn record_success(&self, rtt_ns: i64, now_ns: i64) {
        let mut state = self.write();
        state.last_success_ns = now_ns;
        state.failure_count = 0;
        state.circuit_open_until_ns = 0;
        state.probe_in_flight = false;
        state.fail_rate *= 1.0 - FAIL_RATE_ALPHA;
        state.observe_rtt(rtt_ns);
    }

    /// `RecordFailure`: one failed attempt (`weight = 1`).
    pub fn record_failure(&self, now_ns: i64) {
        self.record_failure_weight(1, now_ns);
    }

    /// `RecordPolicyFailure`: a policy/configuration rejection (REFUSED, FORMERR, NOTIMP) counted
    /// with the trip threshold as its weight, so the circuit opens at once.
    pub fn record_policy_failure(&self, now_ns: i64) {
        self.record_failure_weight(CIRCUIT_TRIP_THRESHOLD, now_ns);
    }

    /// `recordFailureWeight`: the shared body of the two failure entries above.
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
            // `circuitBaseCooldown << shift`, capped: 5 s doubling up to 60 s.
            let cooldown = (CIRCUIT_BASE_COOLDOWN_NS << shift).min(CIRCUIT_MAX_COOLDOWN_NS);
            state.circuit_open_until_ns = now_ns.saturating_add(cooldown);
        }
    }

    /// `AllowAttempt`: while the circuit is open nothing is tried; once the cooldown expired a
    /// single half-open probe is allowed, and further attempts wait for its outcome.
    pub fn allow_attempt(&self, now_ns: i64) -> bool {
        let mut state = self.write();
        if state.circuit_open_until_ns == 0 {
            return true;
        }
        if now_ns < state.circuit_open_until_ns {
            return false;
        }
        if state.probe_in_flight {
            return false;
        }
        state.probe_in_flight = true;
        true
    }

    /// `RecordCensored`: the query was cancelled because another provider answered first. It is
    /// not a failure, but the provider was at least `elapsed_ns` slow, so it is used as a lower
    /// bound RTT sample when it exceeds SRTT.
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

    /// `scoreAt`: expected cost of using this provider at `now_ns`.
    pub fn score(&self, now_ns: i64) -> i64 {
        self.read().score_at(now_ns)
    }

    /// `HedgeDelay`: how long `smart_prediction` waits before launching the next candidate
    /// (SRTT + 2*RTTVAR, clamped to [20 ms, 800 ms]; 50 ms without samples).
    pub fn hedge_delay(&self) -> i64 {
        self.read().tail_latency(
            HEDGE_DELAY_COLD_NS,
            HEDGE_VAR_FACTOR,
            HEDGE_DELAY_MIN_NS,
            HEDGE_DELAY_MAX_NS,
        )
    }

    /// `AttemptTimeout`: per-attempt timeout of sequential failover
    /// (SRTT + 4*RTTVAR, clamped to [300 ms, 2 s]; 1.5 s without samples).
    pub fn attempt_timeout(&self) -> i64 {
        self.read().tail_latency(
            ATTEMPT_TIMEOUT_COLD_NS,
            ATTEMPT_VAR_FACTOR,
            ATTEMPT_TIMEOUT_MIN_NS,
            ATTEMPT_TIMEOUT_MAX_NS,
        )
    }

    /// `UDPRetryDelay`: initial read timeout before retrying a plain UDP packet on the same
    /// upstream (SRTT + 4*RTTVAR, clamped to [200 ms, 1.5 s]; 400 ms without samples).
    pub fn udp_retry_delay(&self) -> i64 {
        self.read().tail_latency(
            UDP_RETRY_DELAY_COLD_NS,
            UDP_RETRY_VAR_FACTOR,
            UDP_RETRY_DELAY_MIN_NS,
            UDP_RETRY_DELAY_MAX_NS,
        )
    }

    /// Whole state, for the tests and the corpus replay.
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

    /// Number of RTT samples folded in so far (the Go test's white-box counter).
    pub fn sample_count(&self) -> i64 {
        self.read().sample_count
    }

    /// Consecutive failures since the last success (the Go test's white-box counter).
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
