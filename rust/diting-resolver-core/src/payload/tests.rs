//! The session-request decoder and the step-response encoder, byte for byte.

use super::*;
use crate::schedule::{PlanInput, Provider};

fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

/// Builds a session request the way the Go encoder does.
fn encode_plan(input: &PlanInput) -> Vec<u8> {
    let mut out = vec![LAYOUT_VERSION];
    let code = match input.strategy {
        Strategy::Single => 0,
        Strategy::PrimaryBackup => 1,
        Strategy::ParallelRace => 2,
        Strategy::SmartPrediction => 3,
    };
    out.push(code);
    out.extend_from_slice(&(input.providers.len() as u32).to_le_bytes());
    for provider in &input.providers {
        put_text(&mut out, &provider.id);
        out.push(u8::from(provider.encrypted));
        out.push(u8::from(provider.allow_attempt));
        out.extend_from_slice(&provider.score_ns.to_le_bytes());
        out.extend_from_slice(&provider.hedge_delay_ns.to_le_bytes());
        out.extend_from_slice(&provider.attempt_timeout_ns.to_le_bytes());
    }
    out.extend_from_slice(&input.race_max_parallel.to_le_bytes());
    out.extend_from_slice(&input.query_budget_ns.to_le_bytes());
    out.extend_from_slice(&input.encrypted_window_ns.to_le_bytes());
    out
}

fn sample() -> PlanInput {
    PlanInput {
        strategy: Strategy::SmartPrediction,
        providers: vec![
            Provider {
                id: "primary".to_string(),
                encrypted: false,
                score_ns: 5_000_000,
                hedge_delay_ns: 40_000_000,
                attempt_timeout_ns: 1_500_000_000,
                allow_attempt: true,
            },
            Provider {
                id: "doh".to_string(),
                encrypted: true,
                score_ns: 20_000_000,
                hedge_delay_ns: 50_000_000,
                attempt_timeout_ns: 1_000_000_000,
                allow_attempt: false,
            },
        ],
        race_max_parallel: 1,
        query_budget_ns: 5_000_000_000,
        encrypted_window_ns: 25_000_000,
    }
}

#[test]
fn the_session_request_round_trips() {
    let input = sample();
    let decoded = decode_plan(&encode_plan(&input)).expect("payload decodes");
    assert_eq!(decoded, input);
}

#[test]
fn a_drifted_payload_is_rejected() {
    let encoded = encode_plan(&sample());

    let mut bad_layout = encoded.clone();
    bad_layout[0] = LAYOUT_VERSION + 1;
    assert!(decode_plan(&bad_layout).is_none());

    let mut unknown_strategy = encoded.clone();
    unknown_strategy[1] = 9;
    assert!(decode_plan(&unknown_strategy).is_none());

    let mut trailing = encoded.clone();
    trailing.push(0);
    assert!(decode_plan(&trailing).is_none());

    assert!(decode_plan(&encoded[..encoded.len() - 1]).is_none());
}

#[test]
fn a_step_response_encodes_the_actions() {
    let step = Step {
        launches: vec![
            Launch {
                provider: 3,
                timeout_ns: 0,
            },
            Launch {
                provider: 7,
                timeout_ns: 250_000_000,
            },
        ],
        hedge: Hedge::Arm(40_000_000),
        grace: Some(25_000_000),
        outcome: None,
    };
    let encoded = encode_step(&step);
    assert_eq!(encoded[0], LAYOUT_VERSION);
    assert_eq!(encoded[1], HEDGE_ARM);
    assert_eq!(
        i64::from_le_bytes(encoded[2..10].try_into().unwrap()),
        40_000_000
    );
    assert_eq!(encoded[10], GRACE_ARM);
    assert_eq!(
        i64::from_le_bytes(encoded[11..19].try_into().unwrap()),
        25_000_000
    );
    assert_eq!(u32::from_le_bytes(encoded[19..23].try_into().unwrap()), 2);
    assert_eq!(u32::from_le_bytes(encoded[23..27].try_into().unwrap()), 3);
    assert_eq!(i64::from_le_bytes(encoded[27..35].try_into().unwrap()), 0);
    assert_eq!(u32::from_le_bytes(encoded[35..39].try_into().unwrap()), 7);
    assert_eq!(
        i64::from_le_bytes(encoded[39..47].try_into().unwrap()),
        250_000_000
    );
    // Not terminal.
    assert_eq!(encoded[47], 0);
    assert_eq!(encoded.len(), 48);
}

#[test]
fn a_terminal_event_round_trips_through_the_shared_layout() {
    let mut schedule = crate::schedule::Schedule::new(sample()).unwrap();
    let start = schedule.start();
    assert_eq!(start.launches.len(), 1);
    schedule.launched(0, true);
    let step = schedule.result(0, true, 5_000_000, 6_000_000, false, None);
    let encoded = encode_step(&step);
    assert_eq!(encoded[0], LAYOUT_VERSION);
    // The closing step carries no launches: the terminal block starts right after the header.
    let terminal_at = 23;
    assert_eq!(encoded[terminal_at], 1);
    assert_eq!(encoded[terminal_at + 1], OUTCOME_EVENT);
    assert_eq!(encoded[terminal_at + 2], 1); // success
    let length = u32::from_le_bytes(
        encoded[terminal_at + 3..terminal_at + 7]
            .try_into()
            .unwrap(),
    );
    assert_eq!(
        &encoded[terminal_at + 7..terminal_at + 7 + length as usize],
        b"smart_prediction"
    );
}

#[test]
fn a_silent_failure_encodes_its_text() {
    let step = Step {
        launches: Vec::new(),
        hedge: Hedge::Disarm,
        grace: None,
        outcome: Some(Outcome::Silent("no providers available".to_string())),
    };
    let encoded = encode_step(&step);
    assert_eq!(encoded[1], HEDGE_DISARM);
    assert_eq!(encoded[10], GRACE_NONE);
    assert_eq!(u32::from_le_bytes(encoded[19..23].try_into().unwrap()), 0);
    assert_eq!(encoded[23], 1);
    assert_eq!(encoded[24], OUTCOME_SILENT);
    let length = u32::from_le_bytes(encoded[25..29].try_into().unwrap()) as usize;
    assert_eq!(&encoded[29..29 + length], b"no providers available");
    assert_eq!(encoded.len(), 29 + length);
}
