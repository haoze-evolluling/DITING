//! The binary layouts shared with `android/engine/resolver_schedule*.go`.
//!
//! Session request (one per query):
//!
//! ```text
//! u8 layout | u8 strategy | u32 provider_count
//!   per provider: text id | u8 encrypted | u8 allow_attempt
//!                 i64 score_ns | i64 hedge_delay_ns | i64 attempt_timeout_ns
//! u32 race_max_parallel | i64 query_budget_ns | i64 encrypted_window_ns
//! ```
//!
//! Step response (one per event):
//!
//! ```text
//! u8 layout | u8 hedge_mode | i64 hedge_ns | u8 grace_mode | i64 grace_ns
//! u32 launch_count
//!   per launch: u32 provider | i64 timeout_ns
//! u8 terminal
//!   terminal event:  u8 0 | u8 success | text strategy | u32 provider_count | i64 elapsed_ms
//!                    text selected_id | i64 selected_elapsed_ms | text winner_id
//!                    i32 winner_index | i64 winner_elapsed_ms
//!                    u8 fallback_used | u8 fallback_success | text error_message
//!   terminal silent: u8 1 | text message
//! ```
//!
//! `text` is `u32 length | bytes`; every integer is little-endian. A drifted version byte, a length
//! that disagrees with the payload or a trailing byte is a hard error.

use crate::schedule::{Event, Hedge, Launch, Outcome, PlanInput, Provider, Step, Strategy};

/// Must match `resolverSchedulePayloadLayoutVersion` in Go.
pub const LAYOUT_VERSION: u8 = 1;

const HEDGE_LEAVE: u8 = 0;
const HEDGE_ARM: u8 = 1;
const HEDGE_DISARM: u8 = 2;

const GRACE_NONE: u8 = 0;
const GRACE_ARM: u8 = 1;

const OUTCOME_EVENT: u8 = 0;
const OUTCOME_SILENT: u8 = 1;

struct Reader<'a> {
    payload: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(payload: &'a [u8]) -> Option<Self> {
        if payload.first().copied()? != LAYOUT_VERSION {
            return None;
        }
        Some(Self {
            payload,
            position: 1,
        })
    }

    fn take(&mut self, length: usize) -> Option<&'a [u8]> {
        if self.payload.len() - self.position < length {
            return None;
        }
        let slice = &self.payload[self.position..self.position + length];
        self.position += length;
        Some(slice)
    }

    fn u8(&mut self) -> Option<u8> {
        Some(self.take(1)?[0])
    }

    fn u32(&mut self) -> Option<u32> {
        Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
    }

    fn i64(&mut self) -> Option<i64> {
        Some(i64::from_le_bytes(self.take(8)?.try_into().ok()?))
    }

    fn text(&mut self) -> Option<String> {
        let length = self.u32()? as usize;
        Some(String::from_utf8_lossy(self.take(length)?).into_owned())
    }

    fn finished(&self) -> bool {
        self.position == self.payload.len()
    }
}

fn put_text(out: &mut Vec<u8>, text: &str) {
    out.extend_from_slice(&(text.len() as u32).to_le_bytes());
    out.extend_from_slice(text.as_bytes());
}

/// Decodes one session request.
pub fn decode_plan(payload: &[u8]) -> Option<PlanInput> {
    let mut reader = Reader::new(payload)?;
    let strategy = Strategy::from_code(reader.u8()?)?;
    let count = reader.u32()? as usize;
    let mut providers = Vec::with_capacity(count.min(1024));
    for _ in 0..count {
        let id = reader.text()?;
        let encrypted = reader.u8()? != 0;
        let allow_attempt = reader.u8()? != 0;
        let score_ns = reader.i64()?;
        let hedge_delay_ns = reader.i64()?;
        let attempt_timeout_ns = reader.i64()?;
        providers.push(Provider {
            id,
            encrypted,
            score_ns,
            hedge_delay_ns,
            attempt_timeout_ns,
            allow_attempt,
        });
    }
    let race_max_parallel = reader.u32()?;
    let query_budget_ns = reader.i64()?;
    let encrypted_window_ns = reader.i64()?;
    if !reader.finished() {
        return None;
    }
    Some(PlanInput {
        strategy,
        providers,
        race_max_parallel,
        query_budget_ns,
        encrypted_window_ns,
    })
}

/// Encodes one step response.
pub fn encode_step(step: &Step) -> Vec<u8> {
    let mut out = Vec::with_capacity(96);
    out.push(LAYOUT_VERSION);
    match step.hedge {
        Hedge::Leave => {
            out.push(HEDGE_LEAVE);
            out.extend_from_slice(&0i64.to_le_bytes());
        }
        Hedge::Arm(delay_ns) => {
            out.push(HEDGE_ARM);
            out.extend_from_slice(&delay_ns.to_le_bytes());
        }
        Hedge::Disarm => {
            out.push(HEDGE_DISARM);
            out.extend_from_slice(&0i64.to_le_bytes());
        }
    }
    match step.grace {
        Some(window_ns) => {
            out.push(GRACE_ARM);
            out.extend_from_slice(&window_ns.to_le_bytes());
        }
        None => {
            out.push(GRACE_NONE);
            out.extend_from_slice(&0i64.to_le_bytes());
        }
    }
    out.extend_from_slice(&(step.launches.len() as u32).to_le_bytes());
    for launch in &step.launches {
        put_launch(&mut out, launch);
    }
    match &step.outcome {
        None => out.push(0),
        Some(Outcome::Event(event)) => {
            out.push(1);
            out.push(OUTCOME_EVENT);
            put_event(&mut out, event);
        }
        Some(Outcome::Silent(message)) => {
            out.push(1);
            out.push(OUTCOME_SILENT);
            put_text(&mut out, message);
        }
    }
    out
}

fn put_launch(out: &mut Vec<u8>, launch: &Launch) {
    out.extend_from_slice(&launch.provider.to_le_bytes());
    out.extend_from_slice(&launch.timeout_ns.to_le_bytes());
}

fn put_event(out: &mut Vec<u8>, event: &Event) {
    out.push(u8::from(event.success));
    put_text(out, event.strategy);
    out.extend_from_slice(&(event.provider_count as u32).to_le_bytes());
    out.extend_from_slice(&event.elapsed_ms.to_le_bytes());
    put_text(out, &event.selected_id);
    out.extend_from_slice(&event.selected_elapsed_ms.to_le_bytes());
    put_text(out, &event.winner_id);
    out.extend_from_slice(
        &event
            .winner_index
            .map_or(-1i32, |index| index as i32)
            .to_le_bytes(),
    );
    out.extend_from_slice(&event.winner_elapsed_ms.to_le_bytes());
    out.push(u8::from(event.fallback_used));
    out.push(u8::from(event.fallback_success));
    put_text(out, &event.error_message);
}

#[cfg(test)]
mod tests;
