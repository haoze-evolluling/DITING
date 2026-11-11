//! The VPN-slot watchdog state machine.
//!
//! `onRevoke` fires both when another app takes the slot and when the user disconnects from system
//! settings. Only the first is followed by a foreign VPN network, so a revoke with no VPN inside
//! [`CONFIRM_WINDOW_MS`] is the user's choice. Once occupied, the slot must stay free for
//! [`RELEASE_DEBOUNCE_MS`] before the owner may reclaim it.
//!
//! Kotlin still owns the `ConnectivityManager` callback, the `Handler` timers, the notification and
//! `VpnService.prepare`; this module owns every phase, deadline and poll interval.

/// Wait after `onRevoke` before the first poll; our own network tears down asynchronously.
pub const GRACE_MS: i64 = 2_000;
/// No foreign VPN within this window means the user turned the tunnel off.
pub const CONFIRM_WINDOW_MS: i64 = 15_000;
pub const CONFIRM_POLL_MS: i64 = 1_000;
pub const WATCH_POLL_MS: i64 = 5_000;
/// The slot must stay free this long before reconnecting.
pub const RELEASE_DEBOUNCE_MS: i64 = 3_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Phase {
    #[default]
    Inactive,
    Confirming,
    Occupied,
    Released,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Event {
    #[default]
    None,
    Occupied,
    Released,
    UserDisconnect,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Step {
    pub event: Event,
    pub next_delay_ms: i64,
}

impl Step {
    fn idle(next_delay_ms: i64) -> Self {
        Self {
            event: Event::None,
            next_delay_ms,
        }
    }

    fn event(event: Event, next_delay_ms: i64) -> Self {
        Self {
            event,
            next_delay_ms,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct Watchdog {
    phase: Phase,
    active: bool,
    confirm_deadline: i64,
    free_since: i64,
}

impl Watchdog {
    pub fn new() -> Self {
        Self::default()
    }

    /// Starts a new confirmation window and returns the first poll delay.
    pub fn start(&mut self, now_ms: i64) -> i64 {
        self.active = true;
        self.phase = Phase::Confirming;
        self.free_since = 0;
        self.confirm_deadline = now_ms + CONFIRM_WINDOW_MS;
        GRACE_MS
    }

    pub fn stop(&mut self) {
        self.active = false;
        self.phase = Phase::Inactive;
        self.free_since = 0;
    }

    /// Feeds one poll; the returned delay is what the caller should schedule next (0 means stop).
    pub fn evaluate(&mut self, now_ms: i64, occupied: bool) -> Step {
        if !self.active {
            return Step::idle(0);
        }
        match self.phase {
            Phase::Inactive => Step::idle(0),
            Phase::Confirming => {
                if occupied {
                    self.enter_occupied();
                    Step::event(Event::Occupied, WATCH_POLL_MS)
                } else if now_ms >= self.confirm_deadline {
                    self.stop();
                    Step::event(Event::UserDisconnect, 0)
                } else {
                    Step::idle(CONFIRM_POLL_MS)
                }
            }
            Phase::Occupied => {
                if occupied {
                    self.free_since = 0;
                    Step::idle(WATCH_POLL_MS)
                } else if self.free_since == 0 {
                    self.free_since = now_ms;
                    Step::idle(RELEASE_DEBOUNCE_MS)
                } else {
                    let elapsed = now_ms - self.free_since;
                    if elapsed >= RELEASE_DEBOUNCE_MS {
                        self.phase = Phase::Released;
                        Step::event(Event::Released, WATCH_POLL_MS)
                    } else {
                        Step::idle(RELEASE_DEBOUNCE_MS - elapsed)
                    }
                }
            }
            Phase::Released => {
                if occupied {
                    self.enter_occupied();
                    Step::event(Event::Occupied, WATCH_POLL_MS)
                } else {
                    Step::idle(WATCH_POLL_MS)
                }
            }
        }
    }

    fn enter_occupied(&mut self) {
        self.phase = Phase::Occupied;
        self.free_since = 0;
    }
}

/// Whether a revoke should be followed at all.
pub fn should_follow(
    enabled: bool,
    current_work_mode: &str,
    expected_work_mode: &str,
    has_restore_intent: bool,
) -> bool {
    reclaim_allowed(enabled, current_work_mode, expected_work_mode) && has_restore_intent
}

/// Mode/switch gate, checked before `VpnService.prepare` so a mode change never re-prepares.
pub fn reclaim_allowed(enabled: bool, current_work_mode: &str, expected_work_mode: &str) -> bool {
    enabled && current_work_mode == expected_work_mode
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ReconnectAction {
    Reconnect,
    UserDisconnect,
    NeedsConsent,
    GiveUp,
}

impl ReconnectAction {
    pub fn code(self) -> i32 {
        match self {
            Self::Reconnect => 0,
            Self::UserDisconnect => 1,
            Self::NeedsConsent => 2,
            Self::GiveUp => 3,
        }
    }
}

/// The on-released decision in the legacy order: mode/switch, consent, then the restore intent.
pub fn reconnect_decision(
    enabled: bool,
    current_work_mode: &str,
    expected_work_mode: &str,
    consent_missing: bool,
    has_restore_intent: bool,
) -> ReconnectAction {
    if !reclaim_allowed(enabled, current_work_mode, expected_work_mode) {
        return ReconnectAction::UserDisconnect;
    }
    if consent_missing {
        return ReconnectAction::NeedsConsent;
    }
    if !has_restore_intent {
        return ReconnectAction::GiveUp;
    }
    ReconnectAction::Reconnect
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn confirming_without_a_foreign_vpn_ends_as_user_disconnect() {
        let mut watchdog = Watchdog::new();
        assert_eq!(watchdog.start(1_000), GRACE_MS);
        let step = watchdog.evaluate(3_000, false);
        assert_eq!(step.event, Event::None);
        assert_eq!(step.next_delay_ms, CONFIRM_POLL_MS);

        let step = watchdog.evaluate(1_000 + CONFIRM_WINDOW_MS, false);
        assert_eq!(step.event, Event::UserDisconnect);
        assert_eq!(step.next_delay_ms, 0);
        assert_eq!(watchdog.evaluate(30_000, false).event, Event::None);
    }

    #[test]
    fn occupied_is_followed_by_a_debounced_release() {
        let mut watchdog = Watchdog::new();
        watchdog.start(0);
        let step = watchdog.evaluate(2_000, true);
        assert_eq!(step.event, Event::Occupied);

        let step = watchdog.evaluate(3_000, false);
        assert_eq!(step.event, Event::None);
        assert_eq!(step.next_delay_ms, RELEASE_DEBOUNCE_MS);

        let step = watchdog.evaluate(3_000 + RELEASE_DEBOUNCE_MS - 1, false);
        assert_eq!(step.event, Event::None);
        assert_eq!(step.next_delay_ms, 1);

        let step = watchdog.evaluate(3_000 + RELEASE_DEBOUNCE_MS, false);
        assert_eq!(step.event, Event::Released);
        assert_eq!(step.next_delay_ms, WATCH_POLL_MS);

        // A new VPN after release goes back to occupied instead of confirming.
        let step = watchdog.evaluate(10_000, true);
        assert_eq!(step.event, Event::Occupied);
        assert_eq!(
            watchdog.evaluate(11_000, false).next_delay_ms,
            RELEASE_DEBOUNCE_MS
        );
    }

    #[test]
    fn a_vpn_appearing_during_confirmation_enters_occupied() {
        let mut watchdog = Watchdog::new();
        watchdog.start(0);
        let step = watchdog.evaluate(2_000, true);
        assert_eq!(step.event, Event::Occupied);
        assert_eq!(step.next_delay_ms, WATCH_POLL_MS);
    }

    #[test]
    fn stop_makes_further_polls_inert() {
        let mut watchdog = Watchdog::new();
        watchdog.start(0);
        watchdog.stop();
        let step = watchdog.evaluate(2_000, true);
        assert_eq!(step.event, Event::None);
        assert_eq!(step.next_delay_ms, 0);
    }

    #[test]
    fn follow_and_reconnect_decisions_keep_the_legacy_order() {
        assert!(should_follow(true, "normal", "normal", true));
        assert!(!should_follow(false, "normal", "normal", true));
        assert!(!should_follow(true, "express", "normal", true));
        assert!(!should_follow(true, "normal", "normal", false));
        assert!(reclaim_allowed(true, "express", "express"));
        assert!(!reclaim_allowed(false, "express", "express"));

        assert_eq!(
            reconnect_decision(true, "normal", "normal", false, true),
            ReconnectAction::Reconnect
        );
        assert_eq!(
            reconnect_decision(true, "normal", "normal", true, true),
            ReconnectAction::NeedsConsent
        );
        assert_eq!(
            reconnect_decision(true, "normal", "normal", false, false),
            ReconnectAction::GiveUp
        );
        assert_eq!(
            reconnect_decision(true, "express", "normal", false, true),
            ReconnectAction::UserDisconnect
        );
        assert_eq!(
            reconnect_decision(false, "normal", "normal", false, true),
            ReconnectAction::UserDisconnect
        );
    }
}
