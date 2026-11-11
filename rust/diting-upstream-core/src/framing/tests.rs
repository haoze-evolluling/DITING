use super::*;

#[test]
fn the_request_frame_is_a_two_byte_big_endian_length_then_the_query() {
    let query = [0x12u8, 0x34, 0x56];
    assert_eq!(encode_length_prefixed(&query), vec![0, 3, 0x12, 0x34, 0x56]);
    assert_eq!(encode_length_prefixed(&[]), vec![0, 0]);
}

#[test]
fn the_length_cast_truncates_like_go() {
    // 65537 bytes: Go's `uint16(len)` declares 1 while the body still carries everything.
    let query = vec![0xABu8; 65_537];
    let frame = encode_length_prefixed(&query);
    assert_eq!(&frame[..2], &[0, 1]);
    assert_eq!(frame.len(), 65_539);
}

#[test]
fn frame_into_rejects_a_short_buffer() {
    let query = [1u8, 2, 3];
    let mut out = [0u8; 4];
    assert_eq!(frame_into(&query, &mut out), None);
    let mut out = [0u8; 5];
    assert_eq!(frame_into(&query, &mut out), Some(5));
    assert_eq!(out, [0, 3, 1, 2, 3]);
}

#[test]
fn tcp_lengths_are_unvalidated_but_dot_rejects_zero_and_oversize() {
    assert_eq!(tcp_response_length(&[]), None);
    assert_eq!(tcp_response_length(&[0x01]), None);
    assert_eq!(tcp_response_length(&[0x00, 0x00]), Some(0));
    assert_eq!(tcp_response_length(&[0xFF, 0xFF]), Some(65_535));
    assert_eq!(tcp_response_length(&[0x10, 0x00]), Some(4096));

    assert_eq!(
        dot_response_length(&[0x00, 0x00]),
        Some(DotLength::Invalid(0))
    );
    assert_eq!(
        dot_response_length(&[0x00, 0x05]),
        Some(DotLength::Valid(5))
    );
    assert_eq!(
        dot_response_length(&[0x10, 0x00]),
        Some(DotLength::Valid(4096))
    );
    assert_eq!(
        dot_response_length(&[0x10, 0x01]),
        Some(DotLength::Invalid(4097))
    );
}

#[test]
fn truncation_is_bit_one_of_the_high_flags_byte() {
    let mut raw = vec![0u8; 12];
    assert!(!is_truncated(&raw));
    raw[2] = 0x02;
    assert!(is_truncated(&raw));
    // QR + AA must not be read as TC.
    raw[2] = 0x84;
    assert!(!is_truncated(&raw));
    // A short buffer is never truncated.
    assert!(!is_truncated(&raw[..11]));
    assert!(!is_truncated(&[]));
}

#[test]
fn doq_strips_the_prefix_only_when_it_declares_the_remainder() {
    assert_eq!(doq_skip(&[]), 0);
    assert_eq!(doq_skip(&[0]), 0);
    assert_eq!(doq_skip(&[0, 2, 0xAA, 0xBB]), 2);
    // Declares 5 but only 2 bytes follow: the raw stream is returned.
    assert_eq!(doq_skip(&[0, 5, 0xAA, 0xBB]), 0);
    // Declares 1 while 2 bytes follow.
    assert_eq!(doq_skip(&[0, 1, 0xAA, 0xBB]), 0);
    assert_eq!(doq_skip(&[0, 0]), 2);
}

#[test]
fn the_plain_initial_delay_prefers_a_positive_caller_value() {
    assert_eq!(initial_retry_delay_ns(0), TUNING.plain_retry_default_ns);
    assert_eq!(initial_retry_delay_ns(-1), TUNING.plain_retry_default_ns);
    assert_eq!(initial_retry_delay_ns(400_000_000), 400_000_000);
}

#[test]
fn the_first_deadline_is_clamped_to_the_query_budget() {
    // now=1000, initial=400 -> 1400, deadline 5000.
    assert_eq!(first_deadline_ns(1000, 400, 5000), 1400);
    // The budget is shorter than the initial wait.
    assert_eq!(first_deadline_ns(1000, 400, 1200), 1200);
    // Exactly at the budget keeps the budget.
    assert_eq!(first_deadline_ns(1000, 400, 1400), 1400);
}

#[test]
fn the_retry_deadlines_double_then_use_the_remaining_budget() {
    // Retry 0 waits 2 * initial, clamped to the deadline.
    assert_eq!(retry_deadline_ns(1400, 400, 5000, 0), Some(2200));
    assert_eq!(retry_deadline_ns(4800, 400, 5000, 0), Some(5000));
    // Retry 1 gets the whole remaining budget.
    assert_eq!(retry_deadline_ns(2200, 400, 5000, 1), Some(5000));
    // At or past the deadline there is no retry, and the limit is two retries.
    assert_eq!(retry_deadline_ns(5000, 400, 5000, 0), None);
    assert_eq!(retry_deadline_ns(5001, 400, 5000, 1), None);
    assert_eq!(retry_deadline_ns(1000, 400, 5000, 2), None);
}
