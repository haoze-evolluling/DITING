//! One query's sequential attempt walk.
//!
//! `single` and `primary_backup` run one attempt at a time; the ordering, the budget clipping and the
//! closing race-log line are decided here, while [`super::Schedule`] keeps the state.

use super::*;

impl Schedule {
    pub(super) fn sequential_result(
        &mut self,
        provider: u32,
        ok: bool,
        elapsed_ns: i64,
        since_start_ns: i64,
        parent_cancelled: bool,
        error: Option<&str>,
    ) -> Step {
        let elapsed_ms = elapsed_ns / NS_PER_MS;
        let total_ms = since_start_ns / NS_PER_MS;
        let winner_id = self.provider_id(provider);
        let primary_id = self.provider_id(0);
        let Mode::Sequential(sequential) = &mut self.mode else {
            return Step::idle();
        };
        let position = sequential
            .order
            .iter()
            .position(|&index| index == provider)
            .unwrap_or(sequential.next.saturating_sub(1));
        // `item.idx == 0`: the first *configured* provider, even when the circuit breaker pushed
        // it to the end of the attempt order.
        if provider == 0 {
            sequential.primary_elapsed_ms = elapsed_ms;
        }
        if ok {
            let single = self.strategy == Strategy::Single;
            let fallback_used = !single && (position > 0 || provider != 0);
            let fallback_success = !single && provider != 0;
            let selected_elapsed_ms = if single {
                elapsed_ms
            } else {
                sequential.primary_elapsed_ms
            };
            return Step::event(Event {
                success: true,
                strategy: self.strategy.label(),
                provider_count: self.input.providers.len(),
                elapsed_ms: total_ms,
                selected_id: if single {
                    winner_id.clone()
                } else {
                    primary_id
                },
                selected_elapsed_ms,
                winner_id,
                winner_index: Some(provider),
                winner_elapsed_ms: elapsed_ms,
                fallback_used,
                fallback_success,
                error_message: String::new(),
            });
        }
        if self.strategy == Strategy::Single {
            return Step::event(Event {
                success: false,
                strategy: self.strategy.label(),
                provider_count: self.input.providers.len(),
                elapsed_ms: total_ms,
                selected_id: winner_id.clone(),
                selected_elapsed_ms: elapsed_ms,
                winner_id: String::new(),
                winner_index: None,
                winner_elapsed_ms: 0,
                fallback_used: false,
                fallback_success: false,
                error_message: error.unwrap_or_default().to_string(),
            });
        }
        if let Some(text) = error {
            if !text.is_empty() {
                sequential.errors.push(format!("{winner_id}: {text}"));
            }
        }
        sequential.next = position + 1;
        if !parent_cancelled && since_start_ns < self.input.query_budget_ns {
            if let Some(&next) = sequential.order.get(sequential.next) {
                let remaining = self.input.query_budget_ns - since_start_ns;
                let timeout =
                    sequential_timeout(&self.input, &sequential.order, sequential.next, remaining);
                if timeout > 0 {
                    return Step::launch(next, timeout);
                }
            }
        }
        Step::event(Event {
            success: false,
            strategy: self.strategy.label(),
            provider_count: self.input.providers.len(),
            elapsed_ms: total_ms,
            selected_id: primary_id,
            selected_elapsed_ms: sequential.primary_elapsed_ms,
            winner_id: String::new(),
            winner_index: None,
            winner_elapsed_ms: 0,
            fallback_used: self.input.providers.len() > 1,
            fallback_success: false,
            error_message: sequential.errors.join("\n"),
        })
    }
}
