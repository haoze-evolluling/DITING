//! The `< 1` defaults.

use super::*;

#[test]
fn non_positive_values_fall_back() {
    for input in [0, -1, i64::MIN] {
        let block = DynamicBlock::normalized(true, input, input, input);
        assert_eq!(block.request_threshold, DEFAULT_REQUEST_THRESHOLD);
        assert_eq!(block.window_seconds, DEFAULT_WINDOW_SECONDS);
        assert_eq!(block.nxdomain_seconds, DEFAULT_NXDOMAIN_SECONDS);
    }
}

#[test]
fn positive_values_are_kept() {
    let block = DynamicBlock::normalized(false, 1, 2, 3);
    assert!(!block.enabled);
    assert_eq!(
        (
            block.request_threshold,
            block.window_seconds,
            block.nxdomain_seconds
        ),
        (1, 2, 3)
    );
    // Each field is independent: one zero does not reset the others.
    let mixed = DynamicBlock::normalized(true, 7, 0, 900);
    assert_eq!(
        (
            mixed.request_threshold,
            mixed.window_seconds,
            mixed.nxdomain_seconds
        ),
        (7, DEFAULT_WINDOW_SECONDS, 900)
    );
}

#[test]
fn defaults_match_the_old_config() {
    assert_eq!(
        (
            DEFAULT_REQUEST_THRESHOLD,
            DEFAULT_WINDOW_SECONDS,
            DEFAULT_NXDOMAIN_SECONDS
        ),
        (5, 60, 300)
    );
}
