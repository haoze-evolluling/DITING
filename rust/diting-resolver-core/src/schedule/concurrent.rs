//! The parallel_race / smart_prediction attempt tree.
//!
//! Launches radiate from [`super::Schedule::launched`], results fold back in, and the two timers
//! (staggered hedge, encrypted preference window) decide when the next candidate starts or when a
//! held plain answer wins.

use super::*;

impl Schedule {
    pub(super) fn concurrent_result(
        &mut self,
        provider: u32,
        ok: bool,
        elapsed_ns: i64,
        since_start_ns: i64,
        error: Option<&str>,
    ) -> Step {
        let elapsed_ms = elapsed_ns / NS_PER_MS;
        let provider_id = self.provider_id(provider);
        let Mode::Concurrent(concurrent) = &mut self.mode else {
            return Step::idle();
        };
        let provider_entry = self.input.providers.get(provider as usize);
        let encrypted = provider_entry.is_some_and(|entry| entry.encrypted);
        let position = concurrent
            .candidates
            .iter()
            .position(|&index| index == provider);
        concurrent.inflight = concurrent.inflight.saturating_sub(1);
        if encrypted {
            concurrent.inflight_encrypted = concurrent.inflight_encrypted.saturating_sub(1);
        }
        if position == Some(0) {
            concurrent.primary_elapsed_ms = elapsed_ms;
        }
        if ok {
            // A plain answer in a mixed race waits for the encrypted attempts in flight; the first
            // plain answer is the one held, later ones are dropped (they were dropped before too).
            let hold = concurrent.prefer_encrypted_window_ns > 0
                && !encrypted
                && concurrent.inflight_encrypted > 0;
            if !hold {
                return self.terminal(true, Some((provider, elapsed_ms)), since_start_ns);
            }
            if concurrent.buffered_plain.is_none() {
                concurrent.buffered_plain = Some((provider, elapsed_ms));
                return Step {
                    grace: Some(concurrent.prefer_encrypted_window_ns),
                    ..Step::idle()
                };
            }
        } else if let Some(text) = error {
            if !text.is_empty() {
                concurrent.errors.push(format!("{provider_id}: {text}"));
            }
            if concurrent.advance_on_error && concurrent.next < concurrent.candidates.len() {
                return concurrent.request_next();
            }
        }
        // The old loop-top check: a buffered plain answer wins as soon as no encrypted attempt is
        // left in flight.
        if let Some(buffered) = concurrent.buffered_plain {
            if concurrent.inflight_encrypted == 0 {
                return self.terminal(true, Some(buffered), since_start_ns);
            }
        }
        if concurrent.inflight == 0 && concurrent.buffered_plain.is_none() {
            return self.terminal(false, None, since_start_ns);
        }
        Step::idle()
    }

    /// Builds the closing event and marks the session decided.
    pub(super) fn terminal(
        &self,
        success: bool,
        winner: Option<(u32, i64)>,
        since_start_ns: i64,
    ) -> Step {
        let Mode::Concurrent(concurrent) = &self.mode else {
            return Step::idle();
        };
        let winner_position = winner.and_then(|(provider, _)| {
            concurrent
                .candidates
                .iter()
                .position(|&index| index == provider)
        });
        let fallback_used = concurrent.track_fallback && concurrent.spawned > 1;
        let fallback_success =
            concurrent.track_fallback && winner_position.is_some_and(|pos| pos > 0);
        let selected_id = if self.strategy == Strategy::ParallelRace {
            // The race plan never set a primary, so the field was empty before too.
            String::new()
        } else {
            concurrent
                .candidates
                .first()
                .map_or_else(String::new, |&index| self.provider_id(index))
        };
        let selected_elapsed_ms = if success && !concurrent.record_selected_on_success {
            0
        } else if winner_position == Some(0) {
            winner.map_or(0, |(_, elapsed_ms)| elapsed_ms)
        } else {
            concurrent.primary_elapsed_ms
        };
        let (winner_id, winner_index, winner_elapsed_ms) = match winner {
            Some((provider, elapsed_ms)) => {
                (self.provider_id(provider), Some(provider), elapsed_ms)
            }
            None => (String::new(), None, 0),
        };
        Step::event(Event {
            success,
            strategy: self.strategy.label(),
            provider_count: self.input.providers.len(),
            elapsed_ms: since_start_ns / NS_PER_MS,
            selected_id,
            selected_elapsed_ms,
            winner_id,
            winner_index,
            winner_elapsed_ms,
            fallback_used,
            fallback_success,
            error_message: if success {
                String::new()
            } else {
                concurrent.errors.join("\n")
            },
        })
    }
}

impl Concurrent {
    pub(super) fn start(&mut self) -> Step {
        self.request_next()
    }

    /// Hands out the next candidate; the caller confirms it with [`Schedule::launched`].
    pub(super) fn request_next(&mut self) -> Step {
        let Some(&provider) = self.candidates.get(self.next) else {
            return Step::idle();
        };
        self.next += 1;
        self.request = Some(provider);
        Step::launch(provider, 0)
    }
}
