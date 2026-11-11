use super::*;

#[test]
fn record_ignores_unattributable_uids_and_non_positive_counts() {
    let tracker = TrafficTracker::new();
    tracker.record(0, 10, 10);
    tracker.record(-1, 10, 10);
    tracker.record(1000, 0, 0);
    tracker.record(1000, -5, -5);
    assert_eq!(tracker.unique_uids(), 0);
    assert!(tracker.tick().is_empty());
    assert_eq!(tracker.totals(1000), None);
}

#[test]
fn record_adds_both_sides_and_tick_swaps_the_deltas() {
    let tracker = TrafficTracker::new();
    tracker.record(1000, 5, 0);
    tracker.record(1000, 0, 7);
    tracker.record(1000, 1, 1);
    tracker.record(1001, 4096, 0);

    let mut deltas = tracker.tick();
    deltas.sort_by_key(|delta| delta.uid);
    assert_eq!(
        deltas,
        vec![
            Delta {
                uid: 1000,
                tx: 6,
                rx: 8,
            },
            Delta {
                uid: 1001,
                tx: 4096,
                rx: 0,
            },
        ]
    );
    // Totals survive the swap; the deltas are gone, so the next tick is silent.
    assert_eq!(tracker.totals(1000), Some((6, 8)));
    assert!(tracker.tick().is_empty());
    assert_eq!(tracker.unique_uids(), 2);

    tracker.record(1000, 3, 0);
    assert_eq!(
        tracker.tick(),
        vec![Delta {
            uid: 1000,
            tx: 3,
            rx: 0,
        }]
    );
}

#[test]
fn the_tick_interval_ignores_non_positive_updates() {
    let tracker = TrafficTracker::new();
    assert_eq!(tracker.interval_ms(), DEFAULT_TICK_INTERVAL_MS);
    tracker.set_interval_ms(10_000);
    assert_eq!(tracker.interval_ms(), 10_000);
    tracker.set_interval_ms(0);
    tracker.set_interval_ms(-1);
    assert_eq!(tracker.interval_ms(), 10_000);
}

#[test]
fn only_uids_with_traffic_appear_in_a_tick() {
    let tracker = TrafficTracker::new();
    tracker.record(1, 1, 0);
    tracker.record(2, 0, 2);
    let deltas = tracker.tick();
    assert_eq!(deltas.len(), 2);
    // Counters stay in the map even when a tick has nothing to report.
    assert_eq!(tracker.unique_uids(), 2);
    assert!(tracker.tick().is_empty());
}
