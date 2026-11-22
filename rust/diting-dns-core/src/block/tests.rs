use super::*;

const S: i64 = 1_000_000_000;

fn config(threshold: u32) -> BlockConfig {
    BlockConfig {
        enabled: true,
        request_threshold: threshold,
        window_ns: 60 * S,
        nx_domain_ns: 30 * S,
    }
}

#[test]
fn below_the_threshold_the_answer_is_nodata() {
    let blocks = DynamicBlocks::new();
    let config = config(2);
    assert_eq!(
        blocks.response_for("a.example", &config, 0, 0),
        RESPONSE_NO_DATA
    );
    assert_eq!(
        blocks.response_for("a.example", &config, 0, S),
        RESPONSE_NO_DATA
    );
}

#[test]
fn crossing_the_threshold_holds_nxdomain_for_the_configured_time() {
    let blocks = DynamicBlocks::new();
    let config = config(2);
    for now in [0, S] {
        assert_eq!(
            blocks.response_for("a.example", &config, 0, now),
            RESPONSE_NO_DATA
        );
    }
    assert_eq!(
        blocks.response_for("a.example", &config, 0, 2 * S),
        RESPONSE_NX_DOMAIN
    );
    assert_eq!(
        blocks.response_for("a.example", &config, 0, 31 * S),
        RESPONSE_NX_DOMAIN
    );
    assert_eq!(
        blocks.response_for("a.example", &config, 0, 32 * S),
        RESPONSE_NX_DOMAIN
    );
    assert_eq!(
        blocks.response_for("a.example", &config, 0, 62 * S),
        RESPONSE_NO_DATA
    );
}

#[test]
fn disabling_passes_the_fallback_and_records_nothing() {
    let blocks = DynamicBlocks::new();
    let disabled = BlockConfig {
        enabled: false,
        ..config(2)
    };
    assert_eq!(
        blocks.response_for("a.example", &disabled, RESPONSE_REFUSED, 0),
        RESPONSE_REFUSED
    );
    assert_eq!(blocks.len(), 0, "a disabled tracker records no state");

    let enabled = config(2);
    assert_eq!(
        blocks.response_for("a.example", &enabled, 0, S),
        RESPONSE_NO_DATA
    );
    assert_eq!(
        blocks.response_for("a.example", &enabled, 0, 2 * S),
        RESPONSE_NO_DATA
    );
    assert_eq!(
        blocks.response_for("a.example", &enabled, 0, 3 * S),
        RESPONSE_NX_DOMAIN
    );
}

#[test]
fn entries_are_capped() {
    let blocks = DynamicBlocks::new();
    let config = config(10);
    for index in 0..(MAX_ENTRIES + 10) {
        let domain = format!("d{index}.example");
        assert_eq!(
            blocks.response_for(&domain, &config, 0, 0),
            RESPONSE_NO_DATA
        );
    }
    assert_eq!(
        blocks.len(),
        MAX_ENTRIES,
        "the bound is observed after insertion"
    );

    blocks.reset();
    assert_eq!(blocks.len(), 0);
}

#[test]
fn a_clock_rewind_inside_the_window_still_counts() {
    let blocks = DynamicBlocks::new();
    let config = config(2);
    assert_eq!(
        blocks.response_for("a.example", &config, 0, 10 * S),
        RESPONSE_NO_DATA
    );
    assert_eq!(
        blocks.response_for("a.example", &config, 0, S),
        RESPONSE_NO_DATA
    );
    assert_eq!(
        blocks.response_for("a.example", &config, 0, 2 * S),
        RESPONSE_NX_DOMAIN
    );
}
