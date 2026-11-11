//! The scheduler state machine, scenario by scenario.
//!
//! Every case is the shape the old Go loop produced: the attempt order, the clipped timeouts, the
//! hedge and grace timers, and the race-log fields. Times are scripted nanoseconds, so nothing here
//! waits on a real timer.

use super::*;

const MS: i64 = 1_000_000;
const BUDGET: i64 = 5_000;
const WINDOW: i64 = 25;

fn provider(id: &str, encrypted: bool, score_ms: i64) -> Provider {
    Provider {
        id: id.to_string(),
        encrypted,
        score_ns: score_ms * MS,
        hedge_delay_ns: 50 * MS,
        attempt_timeout_ns: 1_500 * MS,
        allow_attempt: true,
    }
}

fn plan(strategy: Strategy, providers: Vec<Provider>) -> PlanInput {
    PlanInput {
        strategy,
        providers,
        race_max_parallel: 0,
        query_budget_ns: BUDGET * MS,
        encrypted_window_ns: WINDOW * MS,
    }
}

fn outcome_event(step: &Step) -> &Event {
    match step.outcome.as_ref() {
        Some(Outcome::Event(event)) => event,
        other => panic!("expected an event, got {other:?}"),
    }
}

fn silent(step: &Step) -> &str {
    match step.outcome.as_ref() {
        Some(Outcome::Silent(message)) => message,
        other => panic!("expected a silent failure, got {other:?}"),
    }
}

fn launch(provider: u32, timeout_ms: i64) -> Launch {
    Launch {
        provider,
        timeout_ns: timeout_ms * MS,
    }
}

#[test]
fn single_reports_the_only_attempt() {
    let mut schedule =
        Schedule::new(plan(Strategy::Single, vec![provider("a", false, 50)])).unwrap();
    let step = schedule.start();
    assert_eq!(step.launches, vec![launch(0, 5_000)]);

    let step = schedule.result(0, true, 2 * MS, 3 * MS, false, None);
    let event = outcome_event(&step);
    assert!(event.success);
    assert_eq!(event.strategy, "single");
    assert_eq!(event.provider_count, 1);
    assert_eq!(event.elapsed_ms, 3);
    assert_eq!(event.selected_id, "a");
    assert_eq!(event.selected_elapsed_ms, 2);
    assert_eq!(event.winner_id, "a");
    assert_eq!(event.winner_index, Some(0));
    assert_eq!(event.winner_elapsed_ms, 2);
    assert!(!event.fallback_used);
    assert!(!event.fallback_success);
    assert_eq!(event.error_message, "");
}

#[test]
fn single_failure_keeps_the_raw_error_and_only_tries_the_first_provider() {
    let mut schedule = Schedule::new(plan(
        Strategy::Single,
        vec![provider("a", false, 50), provider("b", false, 50)],
    ))
    .unwrap();
    schedule.start();
    let step = schedule.result(0, false, 4 * MS, 6 * MS, false, Some("boom"));
    let event = outcome_event(&step);
    assert!(!event.success);
    assert_eq!(event.strategy, "single");
    assert_eq!(event.selected_id, "a");
    assert_eq!(event.selected_elapsed_ms, 4);
    assert_eq!(event.winner_id, "");
    assert_eq!(event.winner_index, None);
    assert_eq!(event.error_message, "boom");
}

#[test]
fn primary_backup_clips_each_attempt_to_the_budget_and_fails_over() {
    let mut input = plan(
        Strategy::PrimaryBackup,
        vec![provider("a", false, 50), provider("b", false, 50)],
    );
    input.query_budget_ns = 1_000 * MS;
    let mut schedule = Schedule::new(input).unwrap();
    // Cold attempt timeout is 1.5 s, but the budget is only 1 s.
    assert_eq!(schedule.start().launches, vec![launch(0, 1_000)]);

    let step = schedule.result(0, false, 600 * MS, 600 * MS, false, Some("timeout"));
    // The last attempt takes whatever is left of the budget.
    assert_eq!(step.launches, vec![launch(1, 400)]);
    let step = schedule.result(1, true, 2 * MS, 610 * MS, false, None);
    let event = outcome_event(&step);
    assert!(event.success);
    assert_eq!(event.strategy, "primary_backup");
    assert_eq!(event.selected_id, "a");
    assert_eq!(event.selected_elapsed_ms, 600);
    assert_eq!(event.winner_id, "b");
    assert!(event.fallback_used);
    assert!(event.fallback_success);
}

#[test]
fn primary_backup_attempt_timeout_is_capped_by_the_adaptive_value() {
    let mut input = plan(
        Strategy::PrimaryBackup,
        vec![provider("a", false, 50), provider("b", false, 50)],
    );
    input.query_budget_ns = 5_000 * MS;
    input.providers[0].attempt_timeout_ns = 300 * MS;
    let mut schedule = Schedule::new(input).unwrap();
    assert_eq!(schedule.start().launches, vec![launch(0, 300)]);
    let step = schedule.result(0, false, 200 * MS, 200 * MS, false, Some("timeout"));
    // The last attempt may use the whole remaining budget (`pos == len(order)-1`).
    assert_eq!(step.launches, vec![launch(1, 4_800)]);
}

#[test]
fn primary_backup_gives_up_when_the_budget_is_gone() {
    let mut input = plan(
        Strategy::PrimaryBackup,
        vec![provider("a", false, 50), provider("b", false, 50)],
    );
    input.query_budget_ns = 500 * MS;
    let mut schedule = Schedule::new(input).unwrap();
    // The first attempt already clipped to the whole budget.
    assert_eq!(schedule.start().launches, vec![launch(0, 500)]);
    let step = schedule.result(0, false, 500 * MS, 500 * MS, false, Some("timeout"));
    let event = outcome_event(&step);
    assert!(!event.success);
    assert_eq!(event.error_message, "a: timeout");

    // A failure with budget left fails over; the joined errors are the closing line.
    let mut schedule = Schedule::new(plan(
        Strategy::PrimaryBackup,
        vec![provider("a", false, 50), provider("b", false, 50)],
    ))
    .unwrap();
    schedule.start();
    let step = schedule.result(0, false, 400 * MS, 400 * MS, false, Some("timeout"));
    assert_eq!(step.launches, vec![launch(1, 4_600)]);
    let step = schedule.result(1, false, 500 * MS, 900 * MS, false, Some("refused"));
    let event = outcome_event(&step);
    assert!(!event.success);
    assert_eq!(event.error_message, "a: timeout\nb: refused");
    assert!(event.fallback_used);
    assert!(!event.fallback_success);
    assert_eq!(event.selected_elapsed_ms, 400);
}

#[test]
fn primary_backup_stops_on_a_cancelled_parent() {
    let mut schedule = Schedule::new(plan(
        Strategy::PrimaryBackup,
        vec![provider("a", false, 50), provider("b", false, 50)],
    ))
    .unwrap();
    schedule.start();
    let step = schedule.result(0, false, 20 * MS, 20 * MS, true, Some("canceled"));
    let event = outcome_event(&step);
    assert!(!event.success);
    assert_eq!(event.error_message, "a: canceled");
}

#[test]
fn primary_backup_skips_a_tripped_circuit_first() {
    let mut broken = provider("a", false, 50);
    broken.allow_attempt = false;
    let mut schedule = Schedule::new(plan(
        Strategy::PrimaryBackup,
        vec![broken, provider("b", false, 50)],
    ))
    .unwrap();
    // The circuit-broken provider is the last resort, not the first attempt.
    assert_eq!(schedule.start().launches, vec![launch(1, 1_500)]);
    let step = schedule.result(1, true, 2 * MS, 10 * MS, false, None);
    let event = outcome_event(&step);
    assert_eq!(event.selected_id, "a");
    assert_eq!(event.selected_elapsed_ms, 0);
    assert_eq!(event.winner_id, "b");
    assert!(event.fallback_used);
    assert!(event.fallback_success);
}

#[test]
fn one_provider_always_runs_the_single_path() {
    for strategy in [
        Strategy::PrimaryBackup,
        Strategy::ParallelRace,
        Strategy::SmartPrediction,
    ] {
        let mut schedule =
            Schedule::new(plan(strategy, vec![provider("only", false, 50)])).unwrap();
        assert_eq!(schedule.strategy(), Strategy::Single);
        assert_eq!(schedule.start().launches, vec![launch(0, 5_000)]);
        let step = schedule.result(0, true, MS, 2 * MS, false, None);
        assert_eq!(outcome_event(&step).strategy, "single");
    }
}

#[test]
fn empty_provider_lists_fail_before_anything_is_tried() {
    let mut schedule = Schedule::new(plan(Strategy::ParallelRace, Vec::new())).unwrap();
    assert_eq!(silent(&schedule.start()), NO_PROVIDERS);
}

#[test]
fn smart_prediction_ranks_by_score_and_staggers_the_next_candidate() {
    let mut slow = provider("slow", false, 50);
    slow.hedge_delay_ns = 30 * MS;
    let fast = provider("fast", false, 10);
    let hedge_delay = fast.hedge_delay_ns;
    let mut schedule = Schedule::new(plan(Strategy::SmartPrediction, vec![slow, fast])).unwrap();

    // Lowest score first, so "fast" (index 1) is the primary.
    assert_eq!(schedule.start().launches, vec![launch(1, 0)]);
    let step = schedule.launched(1, true);
    assert_eq!(step.hedge, Hedge::Arm(hedge_delay));

    // A failure advances immediately instead of waiting for the hedge timer.
    let step = schedule.result(1, false, 5 * MS, 6 * MS, false, Some("servfail"));
    assert_eq!(step.launches, vec![launch(0, 0)]);
    let step = schedule.launched(0, true);
    assert_eq!(step.hedge, Hedge::Disarm);

    let step = schedule.result(0, true, 40 * MS, 50 * MS, false, None);
    let event = outcome_event(&step);
    assert!(event.success);
    assert_eq!(event.strategy, "smart_prediction");
    assert_eq!(event.selected_id, "fast");
    assert_eq!(event.selected_elapsed_ms, 5);
    assert_eq!(event.winner_id, "slow");
    assert_eq!(event.winner_index, Some(0));
    assert_eq!(event.winner_elapsed_ms, 40);
    assert!(event.fallback_used);
    assert!(event.fallback_success);
}

#[test]
fn smart_prediction_hedges_on_the_timer() {
    let mut first = provider("first", false, 10);
    first.hedge_delay_ns = 40 * MS;
    let second = provider("second", false, 20);
    let mut schedule = Schedule::new(plan(Strategy::SmartPrediction, vec![first, second])).unwrap();
    assert_eq!(schedule.start().launches, vec![launch(0, 0)]);
    assert_eq!(schedule.launched(0, true).hedge, Hedge::Arm(40 * MS));

    // The hedge fires while the primary is still in flight.
    assert_eq!(schedule.hedge().launches, vec![launch(1, 0)]);
    assert_eq!(schedule.launched(1, true).hedge, Hedge::Disarm);

    // The staggered attempt wins, and the censored primary keeps the "selected" elapsed at 0
    // because its result never arrived.
    let step = schedule.result(1, true, 45 * MS, 50 * MS, false, None);
    let event = outcome_event(&step);
    assert_eq!(event.winner_id, "second");
    assert_eq!(event.selected_id, "first");
    assert_eq!(event.selected_elapsed_ms, 0);
    assert!(event.fallback_used);
    assert!(event.fallback_success);
}

#[test]
fn parallel_race_starts_the_whole_list_and_reports_no_primary() {
    let mut schedule = Schedule::new(plan(
        Strategy::ParallelRace,
        vec![provider("a", false, 10), provider("b", false, 20)],
    ))
    .unwrap();
    let step = schedule.start();
    assert_eq!(step.launches, vec![launch(0, 0)]);
    let step = schedule.launched(0, true);
    assert_eq!(step.launches, vec![launch(1, 0)]);
    assert_eq!(step.hedge, Hedge::Leave);
    assert_eq!(schedule.launched(1, true).hedge, Hedge::Disarm);

    let step = schedule.result(1, true, 5 * MS, 6 * MS, false, None);
    let event = outcome_event(&step);
    assert!(event.success);
    assert_eq!(event.strategy, "parallel_race");
    assert_eq!(event.provider_count, 2);
    assert_eq!(event.selected_id, "");
    assert_eq!(event.selected_elapsed_ms, 0);
    assert_eq!(event.winner_id, "b");
    assert_eq!(event.winner_index, Some(1));
    assert_eq!(event.winner_elapsed_ms, 5);
    assert!(!event.fallback_used);
}

#[test]
fn parallel_race_cap_ranks_the_candidates_and_reports_the_configured_count() {
    let mut input = plan(
        Strategy::ParallelRace,
        vec![
            provider("a", false, 5),
            provider("b", false, 10),
            provider("c", false, 300),
        ],
    );
    input.race_max_parallel = 2;
    let mut schedule = Schedule::new(input).unwrap();
    // The top two by score; the 300 ms provider is not in the first batch.
    assert_eq!(schedule.start().launches, vec![launch(0, 0)]);
    assert_eq!(schedule.launched(0, true).launches, vec![launch(1, 0)]);
    schedule.launched(1, true);
    // Errors advance to the capped-out candidate.
    assert_eq!(
        schedule
            .result(0, false, 5 * MS, 6 * MS, false, Some("servfail"))
            .launches,
        vec![launch(2, 0)]
    );
    schedule.launched(2, true);
    let step = schedule.result(1, true, 20 * MS, 30 * MS, false, None);
    let event = outcome_event(&step);
    assert_eq!(event.provider_count, 3);
    assert_eq!(event.winner_id, "b");
}

#[test]
fn a_mixed_race_holds_the_plain_answer_for_the_grace_window() {
    let input = plan(
        Strategy::ParallelRace,
        vec![provider("plain", false, 10), provider("doh", true, 20)],
    );
    let mut schedule = Schedule::new(input.clone()).unwrap();
    schedule.start();
    schedule.launched(0, true);
    schedule.launched(1, true);

    // The plain answer arrives first: it is buffered, not returned.
    let step = schedule.result(0, true, MS, 2 * MS, false, None);
    assert_eq!(step.grace, Some(WINDOW * MS));
    assert!(step.outcome.is_none());

    // The encrypted attempt answers inside the window and wins.
    let step = schedule.result(1, true, 8 * MS, 10 * MS, false, None);
    let event = outcome_event(&step);
    assert_eq!(event.winner_id, "doh");

    // Without the encrypted answer the grace timer hands the buffered plain one the win.
    let mut schedule = Schedule::new(input).unwrap();
    schedule.start();
    schedule.launched(0, true);
    schedule.launched(1, true);
    schedule.result(0, true, MS, 2 * MS, false, None);
    let step = schedule.grace(30 * MS);
    let won = outcome_event(&step);
    assert_eq!(won.winner_id, "plain");
    assert_eq!(won.winner_elapsed_ms, 1);
}

#[test]
fn a_failed_encrypted_attempt_releases_the_buffered_plain_answer() {
    let mut schedule = Schedule::new(plan(
        Strategy::ParallelRace,
        vec![provider("plain", false, 10), provider("doh", true, 20)],
    ))
    .unwrap();
    schedule.start();
    schedule.launched(0, true);
    schedule.launched(1, true);
    schedule.result(0, true, MS, 2 * MS, false, None);
    let step = schedule.result(1, false, 9 * MS, MS, false, Some("doh failed"));
    let event = outcome_event(&step);
    assert!(event.success);
    assert_eq!(event.winner_id, "plain");
}

#[test]
fn a_homogeneous_race_has_no_grace_window() {
    let mut schedule = Schedule::new(plan(
        Strategy::ParallelRace,
        vec![provider("a", false, 10), provider("b", false, 20)],
    ))
    .unwrap();
    schedule.start();
    schedule.launched(0, true);
    schedule.launched(1, true);
    let step = schedule.result(0, true, MS, 2 * MS, false, None);
    assert_eq!(step.grace, None);
    assert!(step.is_terminal());
}

#[test]
fn a_race_that_fails_everywhere_joins_the_errors() {
    let mut schedule = Schedule::new(plan(
        Strategy::ParallelRace,
        vec![provider("a", false, 10), provider("b", false, 20)],
    ))
    .unwrap();
    schedule.start();
    schedule.launched(0, true);
    schedule.launched(1, true);
    assert!(schedule
        .result(0, false, 5 * MS, 6 * MS, false, Some("servfail"))
        .outcome
        .is_none());
    let step = schedule.result(1, false, 7 * MS, 9 * MS, false, Some("refused"));
    let event = outcome_event(&step);
    assert!(!event.success);
    assert_eq!(event.error_message, "a: servfail\nb: refused");
    assert_eq!(event.winner_index, None);
}

#[test]
fn a_retired_snapshot_is_reported_without_a_race_log_line() {
    let mut schedule = Schedule::new(plan(
        Strategy::ParallelRace,
        vec![provider("a", false, 10), provider("b", false, 20)],
    ))
    .unwrap();
    assert_eq!(schedule.start().launches, vec![launch(0, 0)]);
    // The first candidate is refused: the next one is requested in its place.
    assert_eq!(schedule.launched(0, false).launches, vec![launch(1, 0)]);
    assert_eq!(silent(&schedule.launched(1, false)), SNAPSHOT_RETIRED);
}

#[test]
fn tied_scores_keep_the_configured_order() {
    let mut schedule = Schedule::new(plan(
        Strategy::SmartPrediction,
        vec![
            provider("a", false, 20),
            provider("b", false, 20),
            provider("c", false, 10),
        ],
    ))
    .unwrap();
    assert_eq!(schedule.start().launches, vec![launch(2, 0)]);
    schedule.launched(2, true);
    schedule.hedge();
    assert_eq!(schedule.launched(0, true).hedge, Hedge::Arm(50 * MS));
}
