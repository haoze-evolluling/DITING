//! The upstream query scheduler: which provider a query tries, in which order, and when.
//!
//! This is the decision layer of `android/engine/resolver_strategy.go` and `resolver_smart.go`:
//!
//! * `single` — one attempt against the first configured provider.
//! * `primary_backup` — the configured order, circuit-broken providers moved to the end as a last
//!   resort, each attempt clipped to the remaining query budget.
//! * `parallel_race` — the whole list (or the top `raceMaxParallel` by score) at once, with the
//!   encrypted-upstream grace window when the set mixes plain and encrypted providers.
//! * `smart_prediction` — the ranked list, one attempt first, the next one staggered by the last
//!   provider's hedge delay, and a failed attempt advancing immediately.
//!
//! Go keeps the queries themselves: goroutines, contexts, `time.Timer`s, sockets and the error
//! strings. The kernel is a state machine driven by events (`start`, launch confirmations,
//! results, hedge timer, grace timer) that answers with the next actions (which provider to launch
//! with which timeout, which timer to arm, and the closing race-log event). It reads no clock:
//! Go passes the elapsed nanoseconds, so a scripted sequence replays exactly.

/// Strategy codes of the session payload; they must match the Go encoder.
pub const STRATEGY_SINGLE: u8 = 0;
pub const STRATEGY_PRIMARY_BACKUP: u8 = 1;
pub const STRATEGY_PARALLEL_RACE: u8 = 2;
pub const STRATEGY_SMART_PREDICTION: u8 = 3;

/// The failure text `resolveSingle` / the schedulers return when there is nothing to try.
pub const NO_PROVIDERS: &str = "no providers available";
/// The failure text of a snapshot that retired before the first launch could acquire it.
pub const SNAPSHOT_RETIRED: &str = "snapshot retired: no providers could be acquired";

const NS_PER_MS: i64 = 1_000_000;

/// Which scheduling strategy a query uses.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Strategy {
    Single,
    PrimaryBackup,
    ParallelRace,
    SmartPrediction,
}

impl Strategy {
    /// Decodes the payload code; an unknown code is not a strategy.
    pub fn from_code(code: u8) -> Option<Self> {
        match code {
            STRATEGY_SINGLE => Some(Self::Single),
            STRATEGY_PRIMARY_BACKUP => Some(Self::PrimaryBackup),
            STRATEGY_PARALLEL_RACE => Some(Self::ParallelRace),
            STRATEGY_SMART_PREDICTION => Some(Self::SmartPrediction),
            _ => None,
        }
    }

    /// The `strategy` field of the race-log line, and the key of the four dispatch arms.
    pub fn label(self) -> &'static str {
        match self {
            Self::Single => "single",
            Self::PrimaryBackup => "primary_backup",
            Self::ParallelRace => "parallel_race",
            Self::SmartPrediction => "smart_prediction",
        }
    }
}

/// One configured provider, as the planner sees it.
///
/// The scores, delays and the circuit-breaker verdict come from the statistics kernel; Go reads
/// them once per query (at the query's start time) and passes them in, so the decision never takes
/// a clock or a second lock on this side.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Provider {
    pub id: String,
    pub encrypted: bool,
    pub score_ns: i64,
    pub hedge_delay_ns: i64,
    pub attempt_timeout_ns: i64,
    pub allow_attempt: bool,
}

/// The inputs of one query's plan.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlanInput {
    pub strategy: Strategy,
    pub providers: Vec<Provider>,
    pub race_max_parallel: u32,
    pub query_budget_ns: i64,
    pub encrypted_window_ns: i64,
}

/// One attempt the caller must launch: a provider index and its per-attempt timeout.
///
/// `timeout_ns == 0` means "the caller's query budget is the only timeout" (the concurrent
/// strategies); sequential attempts carry the clipped budget.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Launch {
    pub provider: u32,
    pub timeout_ns: i64,
}

/// What the caller should do with its hedge timer.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Hedge {
    Leave,
    Arm(i64),
    Disarm,
}

/// The closing race-log line, field for field the event Go used to build.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Event {
    pub success: bool,
    pub strategy: &'static str,
    pub provider_count: usize,
    pub elapsed_ms: i64,
    pub selected_id: String,
    pub selected_elapsed_ms: i64,
    pub winner_id: String,
    /// Provider index of the winning attempt; `None` on failure.
    pub winner_index: Option<u32>,
    pub winner_elapsed_ms: i64,
    pub fallback_used: bool,
    pub fallback_success: bool,
    pub error_message: String,
}

/// How the query ended.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Outcome {
    /// A race-log line is reported (`resolveSingle` / the three schedulers on the normal paths).
    Event(Event),
    /// A failure the old code returned without a race-log line (`no providers available`,
    /// `snapshot retired: no providers could be acquired`).
    Silent(String),
}

/// What the caller must do next.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Step {
    /// Attempts to launch, in this order. Each one is confirmed with [`Schedule::launched`].
    pub launches: Vec<Launch>,
    pub hedge: Hedge,
    /// Set when the caller should (re)arm its encrypted grace timer with this window.
    pub grace: Option<i64>,
    /// Set once the query is decided; the caller must stop and use the event (or the error text).
    pub outcome: Option<Outcome>,
}

impl Step {
    fn idle() -> Self {
        Self {
            launches: Vec::new(),
            hedge: Hedge::Leave,
            grace: None,
            outcome: None,
        }
    }

    fn launch(provider: u32, timeout_ns: i64) -> Self {
        Self {
            launches: vec![Launch {
                provider,
                timeout_ns,
            }],
            ..Self::idle()
        }
    }

    /// Whether the query is decided.
    pub fn is_terminal(&self) -> bool {
        self.outcome.is_some()
    }

    fn silent(message: impl Into<String>) -> Self {
        Self {
            outcome: Some(Outcome::Silent(message.into())),
            ..Self::idle()
        }
    }

    fn event(event: Event) -> Self {
        Self {
            outcome: Some(Outcome::Event(event)),
            ..Self::idle()
        }
    }
}

/// One query's scheduler state.
pub struct Schedule {
    input: PlanInput,
    /// The effective strategy: one configured provider always runs the single path, exactly like
    /// the old `resolvePrimaryBackup` / `resolveParallelRace` / `resolveSmartPrediction` delegating
    /// to `resolveSingle`.
    strategy: Strategy,
    mode: Mode,
}

enum Mode {
    Sequential(Sequential),
    Concurrent(Concurrent),
}

struct Sequential {
    /// Provider indices: `allow_attempt` first (configured order), then the circuit-broken ones.
    order: Vec<u32>,
    /// Position of the attempt to launch next.
    next: usize,
    /// Elapsed time of the first provider's attempt, for the race-log `selected` field.
    primary_elapsed_ms: i64,
    errors: Vec<String>,
}

struct Concurrent {
    /// Provider indices in the order the caller will launch them.
    candidates: Vec<u32>,
    /// How many attempts the initial phase should start (`parallel_race` whole list or the
    /// parallel cap, `smart_prediction` 1). A rejected launch does not consume a slot: the old
    /// `launchOne` moved on to the next candidate instead of giving up on the batch.
    initial_batch: usize,
    /// Position of the next candidate to hand out.
    next: usize,
    /// The launch request the caller has not confirmed yet.
    request: Option<u32>,
    inflight: usize,
    inflight_encrypted: usize,
    /// Attempts actually started (a retired snapshot can skip candidates).
    spawned: usize,
    last_launched: Option<u32>,
    /// A plain answer held back for the encrypted grace window: provider index and elapsed ms.
    buffered_plain: Option<(u32, i64)>,
    primary_elapsed_ms: i64,
    advance_on_error: bool,
    prefer_encrypted_window_ns: i64,
    record_selected_on_success: bool,
    track_fallback: bool,
    errors: Vec<String>,
}

impl Schedule {
    /// Builds one query's session. `None` means the payload was structurally impossible (the FFI
    /// rejects it as a bad payload); an empty provider list is valid and fails on `start`.
    pub fn new(input: PlanInput) -> Option<Self> {
        if input.providers.len() > u32::MAX as usize {
            return None;
        }
        let strategy = if input.providers.len() == 1 {
            Strategy::Single
        } else {
            input.strategy
        };
        let mode = match (input.providers.is_empty(), strategy) {
            (true, _) => Mode::Sequential(Sequential {
                order: Vec::new(),
                next: 0,
                primary_elapsed_ms: 0,
                errors: Vec::new(),
            }),
            // `single` never fails over: only the first configured provider is tried.
            (_, Strategy::Single) => Mode::Sequential(Sequential {
                order: vec![0],
                next: 0,
                primary_elapsed_ms: 0,
                errors: Vec::new(),
            }),
            (_, Strategy::PrimaryBackup) => {
                let mut order: Vec<u32> = Vec::with_capacity(input.providers.len());
                let mut skipped: Vec<u32> = Vec::new();
                for (index, provider) in input.providers.iter().enumerate() {
                    if provider.allow_attempt {
                        order.push(index as u32);
                    } else {
                        skipped.push(index as u32);
                    }
                }
                order.extend(skipped);
                Mode::Sequential(Sequential {
                    order,
                    next: 0,
                    primary_elapsed_ms: 0,
                    errors: Vec::new(),
                })
            }
            (_, Strategy::ParallelRace) => {
                let total = input.providers.len();
                let capped =
                    input.race_max_parallel > 0 && (input.race_max_parallel as usize) < total;
                let candidates = if capped {
                    ranked(&input.providers)
                } else {
                    (0..total as u32).collect()
                };
                let initial_batch = if capped {
                    input.race_max_parallel as usize
                } else {
                    total
                };
                let window = if mixed_encryption(&input.providers, &candidates) {
                    input.encrypted_window_ns
                } else {
                    0
                };
                Mode::Concurrent(Concurrent {
                    candidates,
                    initial_batch,
                    next: 0,
                    request: None,
                    inflight: 0,
                    inflight_encrypted: 0,
                    spawned: 0,
                    last_launched: None,
                    buffered_plain: None,
                    primary_elapsed_ms: 0,
                    advance_on_error: capped,
                    prefer_encrypted_window_ns: window,
                    record_selected_on_success: false,
                    track_fallback: false,
                    errors: Vec::new(),
                })
            }
            (_, Strategy::SmartPrediction) => {
                let candidates = ranked(&input.providers);
                Mode::Concurrent(Concurrent {
                    candidates,
                    initial_batch: 1,
                    next: 0,
                    request: None,
                    inflight: 0,
                    inflight_encrypted: 0,
                    spawned: 0,
                    last_launched: None,
                    buffered_plain: None,
                    primary_elapsed_ms: 0,
                    advance_on_error: true,
                    prefer_encrypted_window_ns: 0,
                    record_selected_on_success: true,
                    track_fallback: true,
                    errors: Vec::new(),
                })
            }
        };
        Some(Self {
            input,
            strategy,
            mode,
        })
    }

    /// The effective strategy label (a single provider always reports `single`).
    pub fn strategy(&self) -> Strategy {
        self.strategy
    }

    /// Starts the query: the first sequential attempt, or the concurrent initial batch.
    pub fn start(&mut self) -> Step {
        if self.input.providers.is_empty() {
            return Step::silent(NO_PROVIDERS);
        }
        match &mut self.mode {
            Mode::Sequential(sequential) => {
                sequential.next = 0;
                let provider = sequential.order[0];
                let timeout = sequential_timeout(
                    &self.input,
                    &sequential.order,
                    0,
                    self.input.query_budget_ns,
                );
                Step::launch(provider, timeout)
            }
            Mode::Concurrent(concurrent) => concurrent.start(),
        }
    }

    /// Confirms (or rejects) one launch request.
    ///
    /// A rejected request is a candidate the retired snapshot refused to take: the old `launchOne`
    /// silently moved on to the next index without counting it.
    pub fn launched(&mut self, provider: u32, launched: bool) -> Step {
        let encrypted = self
            .input
            .providers
            .get(provider as usize)
            .is_some_and(|entry| entry.encrypted);
        let Mode::Concurrent(concurrent) = &mut self.mode else {
            return Step::idle();
        };
        if concurrent.request != Some(provider) {
            return Step::idle();
        }
        concurrent.request = None;
        if launched {
            concurrent.spawned += 1;
            concurrent.inflight += 1;
            if encrypted {
                concurrent.inflight_encrypted += 1;
            }
            concurrent.last_launched = Some(provider);
        }
        // A rejected candidate is always replaced by the next one (the old `launchOne` looped
        // instead of giving up); a started one keeps filling the initial batch.
        if (!launched || concurrent.spawned < concurrent.initial_batch)
            && concurrent.next < concurrent.candidates.len()
        {
            return concurrent.request_next();
        }
        if concurrent.spawned == 0 {
            return Step::silent(SNAPSHOT_RETIRED);
        }
        // The old `armHedge` only existed for smart_prediction and only when candidates remained.
        if self.strategy == Strategy::SmartPrediction
            && concurrent.next < concurrent.candidates.len()
        {
            let delay = concurrent
                .last_launched
                .and_then(|index| self.input.providers.get(index as usize))
                .map_or(0, |entry| entry.hedge_delay_ns);
            return Step {
                hedge: Hedge::Arm(delay),
                ..Step::idle()
            };
        }
        Step {
            hedge: Hedge::Disarm,
            ..Step::idle()
        }
    }

    /// Reports the outcome of one attempt.
    pub fn result(
        &mut self,
        provider: u32,
        ok: bool,
        elapsed_ns: i64,
        since_start_ns: i64,
        parent_cancelled: bool,
        error: Option<&str>,
    ) -> Step {
        if self.input.providers.is_empty() {
            return Step::silent(NO_PROVIDERS);
        }
        match &mut self.mode {
            Mode::Sequential(_) => self.sequential_result(
                provider,
                ok,
                elapsed_ns,
                since_start_ns,
                parent_cancelled,
                error,
            ),
            Mode::Concurrent(_) => {
                self.concurrent_result(provider, ok, elapsed_ns, since_start_ns, error)
            }
        }
    }

    /// The smart_prediction hedge timer fired: launch the next candidate, if any.
    pub fn hedge(&mut self) -> Step {
        let Mode::Concurrent(concurrent) = &mut self.mode else {
            return Step::idle();
        };
        if concurrent.next < concurrent.candidates.len() {
            return concurrent.request_next();
        }
        Step {
            hedge: Hedge::Disarm,
            ..Step::idle()
        }
    }

    /// The encrypted grace window expired: the buffered plain answer wins.
    pub fn grace(&mut self, since_start_ns: i64) -> Step {
        let Mode::Concurrent(concurrent) = &self.mode else {
            return Step::idle();
        };
        match concurrent.buffered_plain {
            Some(buffered) => self.terminal(true, Some(buffered), since_start_ns),
            None => Step::idle(),
        }
    }

    fn provider_id(&self, provider: u32) -> String {
        self.input
            .providers
            .get(provider as usize)
            .map_or_else(String::new, |entry| entry.id.clone())
    }
}

/// The attempt timeout of `position` under the remaining budget: the last attempt always takes
/// whatever is left, and no attempt may outlive the budget.
fn sequential_timeout(input: &PlanInput, order: &[u32], position: usize, remaining_ns: i64) -> i64 {
    let last = position + 1 == order.len();
    let attempt = order
        .get(position)
        .and_then(|&index| input.providers.get(index as usize))
        .map_or(remaining_ns, |entry| entry.attempt_timeout_ns);
    if last || attempt > remaining_ns {
        remaining_ns
    } else {
        attempt
    }
}

/// `rankProviders`: ascending score, stable, so providers with the same score keep the configured
/// order.
fn ranked(providers: &[Provider]) -> Vec<u32> {
    let mut indices: Vec<u32> = (0..providers.len() as u32).collect();
    indices.sort_by(|&left, &right| {
        providers[left as usize]
            .score_ns
            .cmp(&providers[right as usize].score_ns)
    });
    indices
}

/// `hasMixedEncryptedAndPlain`.
fn mixed_encryption(providers: &[Provider], candidates: &[u32]) -> bool {
    let mut plain = false;
    let mut encrypted = false;
    for &index in candidates {
        if providers
            .get(index as usize)
            .is_some_and(|entry| entry.encrypted)
        {
            encrypted = true;
        } else {
            plain = true;
        }
        if plain && encrypted {
            return true;
        }
    }
    false
}

mod concurrent;
mod sequential;

#[cfg(test)]
mod tests;
