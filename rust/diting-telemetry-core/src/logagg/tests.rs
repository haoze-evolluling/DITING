use super::*;

fn item(domain: &str) -> LogItem {
    LogItem {
        domain: domain.to_string(),
        blocked: false,
        query_type: 1,
        response_time_ms: 0,
        app_name: String::new(),
        resolved_ips: String::new(),
        blocked_by: String::new(),
        error_message: String::new(),
        cached: false,
        timestamp_ms: 0,
        ttl: 0,
    }
}

fn connection(domain: &str) -> LogItem {
    LogItem {
        blocked_by: "connection".to_string(),
        ..item(domain)
    }
}

#[test]
fn drain_is_fifo_and_reports_the_remainder() {
    let aggregator = LogAggregator::new();
    for index in 0..3 {
        assert_eq!(
            aggregator.push(item(&format!("d{index}.example"))),
            PushOutcome::Buffered
        );
    }
    assert_eq!(aggregator.pending(), 3);

    let (first, remaining) = aggregator.drain(2);
    assert_eq!(remaining, 1);
    assert_eq!(
        first
            .iter()
            .map(|row| row.domain.as_str())
            .collect::<Vec<_>>(),
        vec!["d0.example", "d1.example"]
    );

    let (second, remaining) = aggregator.drain(BATCH_SIZE);
    assert_eq!(remaining, 0);
    assert_eq!(second.len(), 1);
    assert_eq!(second[0].domain, "d2.example");

    let (empty, _) = aggregator.drain(BATCH_SIZE);
    assert!(empty.is_empty());
}

#[test]
fn a_push_that_reaches_a_full_batch_asks_for_a_flush() {
    let aggregator = LogAggregator::new();
    for index in 0..BATCH_SIZE - 1 {
        assert_eq!(
            aggregator.push(item(&format!("d{index}.example"))),
            PushOutcome::Buffered
        );
    }
    assert_eq!(
        aggregator.push(item("last.example")),
        PushOutcome::Full,
        "the 50th queued row must trigger the flush"
    );
    assert_eq!(aggregator.pending(), BATCH_SIZE);
    assert_eq!(aggregator.dropped(), 0);
}

#[test]
fn a_full_buffer_drops_and_counts() {
    let aggregator = LogAggregator::new();
    for index in 0..BUFFER_SIZE {
        assert_ne!(
            aggregator.push(item(&format!("d{index}.example"))),
            PushOutcome::Dropped
        );
    }
    assert_eq!(aggregator.pending(), BUFFER_SIZE);
    assert_eq!(
        aggregator.push(item("overflow.example")),
        PushOutcome::Dropped
    );
    assert_eq!(aggregator.pending(), BUFFER_SIZE);
    assert_eq!(aggregator.dropped(), 1);
    assert_eq!(aggregator.dropped_conn(), 0);
}

#[test]
fn connection_rows_are_shed_above_the_high_water_mark() {
    let aggregator = LogAggregator::new();
    for index in 0..HIGH_WATER_MARK {
        aggregator.push(item(&format!("d{index}.example")));
    }

    // Unblocked connection rows are the first to go.
    assert_eq!(
        aggregator.push(connection("dst.example")),
        PushOutcome::Dropped
    );
    assert_eq!(aggregator.dropped(), 1);
    assert_eq!(aggregator.dropped_conn(), 1);

    // Blocked connection rows, DNS rows and rows with another reason are still queued.
    for row in [
        LogItem {
            blocked: true,
            blocked_by: "connection".to_string(),
            ..item("blocked.example")
        },
        item("dns.example"),
        LogItem {
            blocked_by: "firewall:x".to_string(),
            ..item("firewall.example")
        },
    ] {
        assert_ne!(aggregator.push(row), PushOutcome::Dropped);
    }
    assert_eq!(aggregator.pending(), HIGH_WATER_MARK + 3);
    assert_eq!(aggregator.dropped(), 1);
    assert_eq!(aggregator.dropped_conn(), 1);
}

#[test]
fn connection_rows_below_the_high_water_mark_are_queued() {
    let aggregator = LogAggregator::new();
    for _ in 0..HIGH_WATER_MARK - 1 {
        aggregator.push(item("filler.example"));
    }
    assert_eq!(
        aggregator.push(connection("dst.example")),
        PushOutcome::Full,
        "below the high-water mark the row is queued (and the batch is long since full)"
    );
    assert_eq!(aggregator.pending(), HIGH_WATER_MARK);
    assert_eq!(aggregator.dropped(), 0);
}
