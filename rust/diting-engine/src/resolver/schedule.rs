use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};

use diting_config_core::protocol::Protocol;
use diting_dns_core::message::{status, validate};
use diting_resolver_core::{
    Event, Hedge, Outcome, PlanInput, Provider as PlanProvider, Schedule, Strategy,
};
use diting_upstream_core::plan;
use diting_upstream_core::tuning::TUNING;
use tokio::task::JoinSet;
use tokio::time::Instant as TokioInstant;

use super::{elapsed_ns, now_ns, plain, Inner, RaceEvent, NO_PROVIDER};

const DOH3_ATTEMPT_TIMEOUT: Duration = Duration::from_secs(2);

fn h3_attempt_timeout(budget: Option<Duration>) -> Duration {
    match budget {
        Some(budget) => (budget / 2)
            .min(DOH3_ATTEMPT_TIMEOUT)
            .max(Duration::from_millis(1)),
        None => DOH3_ATTEMPT_TIMEOUT,
    }
}

struct Attempt {
    provider: u32,
    result: Result<Vec<u8>, String>,
    elapsed_ns: i64,
}

pub(crate) async fn resolve(
    inner: &Arc<Inner>,
    query: &[u8],
) -> (Result<Vec<u8>, String>, Option<RaceEvent>) {
    if inner.providers.is_empty() {
        return (Err(NO_PROVIDER.to_string()), None);
    }

    let started = Instant::now();
    let Some(mut schedule) = Schedule::new(plan_input(inner, now_ns())) else {
        return (
            Err("resolver scheduler rejected the plan".to_string()),
            None,
        );
    };

    match schedule.strategy() {
        Strategy::Single | Strategy::PrimaryBackup => {
            sequential(inner, &mut schedule, query, started).await
        }
        Strategy::ParallelRace | Strategy::SmartPrediction => {
            let budget = Duration::from_nanos(TUNING.query_timeout_plain_ns.max(1) as u64);
            let backstop = budget + Duration::from_secs(2);
            match tokio::time::timeout(
                backstop,
                concurrent(inner, &mut schedule, query, started, budget),
            )
            .await
            {
                Ok(result) => result,
                Err(_) => (Err("context deadline exceeded".to_string()), None),
            }
        }
    }
}

fn plan_input(inner: &Inner, now_ns: i64) -> PlanInput {
    let strategy = match plan::strategy(inner.mode) {
        plan::Strategy::Single => Strategy::Single,
        plan::Strategy::PrimaryBackup => Strategy::PrimaryBackup,
        plan::Strategy::ParallelRace => Strategy::ParallelRace,
        plan::Strategy::SmartPrediction => Strategy::SmartPrediction,
    };
    let consult_circuit = strategy == Strategy::PrimaryBackup && inner.providers.len() > 1;
    let providers = inner
        .providers
        .iter()
        .map(|provider| PlanProvider {
            id: provider.id.clone(),
            encrypted: provider.encrypted(),
            score_ns: provider.stats.score(now_ns),
            hedge_delay_ns: provider.stats.hedge_delay(),
            attempt_timeout_ns: provider.stats.attempt_timeout(),
            allow_attempt: !consult_circuit || provider.stats.allow_attempt(now_ns),
        })
        .collect();

    PlanInput {
        strategy,
        providers,
        race_max_parallel: inner.race_max_parallel.clamp(0, u32::MAX as i64) as u32,
        query_budget_ns: TUNING.query_timeout_plain_ns,
        encrypted_window_ns: TUNING.encrypted_preference_window_ns,
    }
}

async fn attempt(
    inner: &Arc<Inner>,
    index: u32,
    query: &[u8],
    budget: Option<Duration>,
) -> Attempt {
    let provider = &inner.providers[index as usize];
    let retry_delay_ns = provider.stats.udp_retry_delay();
    let started = Instant::now();

    let h3_timeout = h3_attempt_timeout(budget);
    let transport = async {
        match provider.protocol {
            Protocol::Plain => {
                plain::query(
                    &inner.dial,
                    &provider.host,
                    &provider.port,
                    query,
                    retry_delay_ns,
                )
                .await
            }
            Protocol::Dot => match &inner.dot {
                Some(dot) => {
                    dot.query(&inner.dial, &provider.host, &provider.port, query)
                        .await
                }
                None => Err("DoT transport is not configured".to_string()),
            },
            Protocol::Doh => match (&inner.doh, &provider.doh_uri) {
                (Some(doh), Some(uri)) => {
                    if provider.force_h3 {
                        let h3 = inner
                            .doh3
                            .as_ref()
                            .ok_or_else(|| "DoH3 transport is not configured".to_string())?;
                        let port = uri.port_u16().unwrap_or(443);
                        let path = uri
                            .path_and_query()
                            .map(|value| value.as_str())
                            .unwrap_or("/dns-query");
                        h3.query(&inner.dial, &provider.host, port, path, query)
                            .await
                    } else if doh.doh3_ready() {
                        if let Some(h3) = &inner.doh3 {
                            let port = doh
                                .doh3_port()
                                .unwrap_or_else(|| uri.port_u16().unwrap_or(443));
                            let path = uri
                                .path_and_query()
                                .map(|value| value.as_str())
                                .unwrap_or("/dns-query");
                            match tokio::time::timeout(
                                h3_timeout,
                                h3.query(&inner.dial, &provider.host, port, path, query),
                            )
                            .await
                            {
                                Ok(Ok(answer)) => {
                                    doh.note_h3_success();
                                    Ok(answer)
                                }
                                Ok(Err(_)) | Err(_) => {
                                    doh.note_h3_failure();
                                    doh.query(uri, query).await
                                }
                            }
                        } else {
                            doh.query(uri, query).await
                        }
                    } else {
                        doh.query(uri, query).await
                    }
                }
                _ => Err("DoH transport is not configured".to_string()),
            },
            Protocol::Doq => match &inner.doq {
                Some(doq) => {
                    doq.query(&inner.dial, &provider.host, &provider.port, query)
                        .await
                }
                None => Err("DoQ transport is not configured".to_string()),
            },
        }
    };
    let outcome = match budget {
        Some(budget) => match tokio::time::timeout(budget, transport).await {
            Ok(result) => result,
            Err(_) => Err("context deadline exceeded".to_string()),
        },
        None => transport.await,
    };

    let mut policy_rejection = false;
    let result = match outcome {
        Ok(response) => {
            let validation = validate(query, &response);
            if validation.status == status::ACCEPTED {
                Ok(response)
            } else {
                policy_rejection = validation.status == status::UPSTREAM_RCODE
                    && plan::is_policy_rejection(i32::from(validation.rcode));
                Err(plain::invalid_answer(&validation))
            }
        }
        Err(error) => Err(error),
    };

    let elapsed_ns = elapsed_ns(started);
    let now = now_ns();
    match &result {
        Ok(_) => provider.stats.record_success(elapsed_ns, now),
        Err(_) if policy_rejection => provider.stats.record_policy_failure(now),
        Err(_) => provider.stats.record_failure(now),
    }

    Attempt {
        provider: index,
        result,
        elapsed_ns,
    }
}

async fn sequential(
    inner: &Arc<Inner>,
    schedule: &mut Schedule,
    query: &[u8],
    started: Instant,
) -> (Result<Vec<u8>, String>, Option<RaceEvent>) {
    let mut step = schedule.start();
    let mut winner: Option<Vec<u8>> = None;

    loop {
        if let Some(outcome) = step.outcome.clone() {
            return finish(outcome, winner);
        }
        let Some(launch) = step.launches.first().copied() else {
            return (
                Err("resolver scheduler returned no attempt".to_string()),
                None,
            );
        };
        let budget_ns = if launch.timeout_ns > 0 {
            launch.timeout_ns
        } else {
            TUNING.query_timeout_plain_ns
        };
        let budget = Duration::from_nanos(budget_ns.max(1) as u64);
        let attempt = attempt(inner, launch.provider, query, Some(budget)).await;

        winner = attempt.result.as_ref().ok().cloned();
        step = schedule.result(
            launch.provider,
            attempt.result.is_ok(),
            attempt.elapsed_ns,
            elapsed_ns(started),
            false,
            attempt.result.as_ref().err().map(String::as_str),
        );
    }
}

async fn concurrent(
    inner: &Arc<Inner>,
    schedule: &mut Schedule,
    query: &[u8],
    started: Instant,
    budget: Duration,
) -> (Result<Vec<u8>, String>, Option<RaceEvent>) {
    let mut join_set: JoinSet<Attempt> = JoinSet::new();
    let mut responses: HashMap<u32, Vec<u8>> = HashMap::new();
    let mut hedge_at: Option<TokioInstant> = None;
    let mut grace_at: Option<TokioInstant> = None;
    let mut step = schedule.start();

    let outcome = loop {
        while step.outcome.is_none() && !step.launches.is_empty() {
            let launch = step.launches[0];
            let inner = Arc::clone(inner);
            let query = query.to_vec();
            join_set
                .spawn(async move { attempt(&inner, launch.provider, &query, Some(budget)).await });
            step = schedule.launched(launch.provider, true);
        }

        match step.hedge {
            Hedge::Arm(delay_ns) => {
                hedge_at = Some(TokioInstant::now() + Duration::from_nanos(delay_ns.max(0) as u64))
            }
            Hedge::Disarm => hedge_at = None,
            Hedge::Leave => {}
        }
        if let Some(window_ns) = step.grace {
            grace_at = Some(TokioInstant::now() + Duration::from_nanos(window_ns.max(1) as u64));
        }
        if let Some(outcome) = step.outcome.clone() {
            break outcome;
        }

        tokio::select! {
            joined = join_set.join_next() => {
                let Some(joined) = joined else {
                    break Outcome::Silent("resolver attempts ended without an answer".to_string());
                };
                match joined {
                    Ok(attempt) => {
                        if let Ok(response) = &attempt.result {
                            responses.insert(attempt.provider, response.clone());
                        }
                        step = schedule.result(
                            attempt.provider,
                            attempt.result.is_ok(),
                            attempt.elapsed_ns,
                            elapsed_ns(started),
                            false,
                            attempt.result.as_ref().err().map(String::as_str),
                        );
                    }
                    Err(error) => {
                        break Outcome::Silent(format!("resolver attempt failed: {error}"));
                    }
                }
            }
            _ = sleep_until(hedge_at), if hedge_at.is_some() => {
                hedge_at = None;
                step = schedule.hedge();
            }
            _ = sleep_until(grace_at), if grace_at.is_some() => {
                grace_at = None;
                step = schedule.grace(elapsed_ns(started));
            }
        }
    };

    join_set.abort_all();

    let winner = match &outcome {
        Outcome::Event(event) if event.success => event
            .winner_index
            .and_then(|index| responses.remove(&index)),
        _ => None,
    };
    finish(outcome, winner)
}

async fn sleep_until(at: Option<TokioInstant>) {
    match at {
        Some(at) => tokio::time::sleep_until(at).await,
        None => std::future::pending().await,
    }
}

fn finish(
    outcome: Outcome,
    winner: Option<Vec<u8>>,
) -> (Result<Vec<u8>, String>, Option<RaceEvent>) {
    match outcome {
        Outcome::Silent(message) => (Err(message), None),
        Outcome::Event(event) => {
            let race = race_event(&event);
            if event.success {
                return match winner {
                    Some(response) => (Ok(response), Some(race)),
                    None => (Err("resolver winner has no answer".to_string()), Some(race)),
                };
            }
            if event.error_message.is_empty() {
                return (Ok(Vec::new()), Some(race));
            }
            (Err(event.error_message), Some(race))
        }
    }
}

fn race_event(event: &Event) -> RaceEvent {
    RaceEvent {
        query_name: String::new(),
        query_type: 0,
        strategy: event.strategy.to_string(),
        provider_count: event.provider_count as i64,
        success: event.success,
        elapsed_ms: event.elapsed_ms,
        selected_provider_id: event.selected_id.clone(),
        selected_elapsed_ms: event.selected_elapsed_ms,
        winner_provider_id: event.winner_id.clone(),
        winner_elapsed_ms: event.winner_elapsed_ms,
        fallback_used: event.fallback_used,
        fallback_success: event.fallback_success,
        error_message: event.error_message.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_strategy_table_matches_the_kernel() {
        assert_eq!(
            plan::strategy("primary_backup"),
            plan::Strategy::PrimaryBackup
        );
        assert_eq!(plan::strategy("race"), plan::Strategy::ParallelRace);
        assert_eq!(plan::strategy("bogus"), plan::Strategy::Single);
    }

    #[test]
    fn a_silent_outcome_carries_no_race_log_line() {
        let (result, race) = finish(Outcome::Silent(NO_PROVIDER.to_string()), None);
        assert_eq!(result.expect_err("no provider"), NO_PROVIDER);
        assert!(race.is_none());
    }

    #[test]
    fn an_empty_error_list_still_reports_success_to_the_caller() {
        let event = Event {
            success: false,
            strategy: "single",
            provider_count: 1,
            elapsed_ms: 3,
            selected_id: String::new(),
            selected_elapsed_ms: 0,
            winner_id: String::new(),
            winner_index: None,
            winner_elapsed_ms: 0,
            fallback_used: false,
            fallback_success: false,
            error_message: String::new(),
        };
        let (result, race) = finish(Outcome::Event(event), None);
        assert_eq!(result.expect("an empty answer"), Vec::<u8>::new());
        assert!(race.is_some());
    }
}
