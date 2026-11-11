use super::*;

#[test]
fn the_table_reports_its_own_shape() {
    let fields = TUNING.fields();
    assert_eq!(fields.len(), 17);
    assert_eq!(TUNING, Tuning::from_fields(fields));
    assert_eq!(TUNING.query_timeout_plain_ns, 5_000_000_000);
    assert_eq!(TUNING.query_timeout_doh_ns, 5_000_000_000);
    assert_eq!(TUNING.query_timeout_dot_ns, 5_000_000_000);
    assert_eq!(TUNING.query_timeout_doq_ns, 5_000_000_000);
    assert_eq!(TUNING.connect_timeout_ns, 3_000_000_000);
    assert_eq!(TUNING.plain_retry_limit, 2);
    assert_eq!(TUNING.plain_retry_default_ns, 1_500_000_000);
    assert_eq!(TUNING.dot_probe_timeout_ns, 2_000_000_000);
    assert_eq!(TUNING.dot_idle_timeout_ms, 15_000);
    assert_eq!(TUNING.dot_max_idle_conns_per_host, 4);
    assert_eq!(TUNING.max_read_bytes, 65_535);
    assert_eq!(TUNING.doh_retry_delay_ns, 10_000_000);
    assert_eq!(TUNING.doh_idle_conn_timeout_ns, 90_000_000_000);
    assert_eq!(TUNING.doh_max_idle_conns, 5);
    assert_eq!(TUNING.doh_max_idle_conns_per_host, 2);
    assert_eq!(TUNING.doq_max_idle_timeout_ns, 30_000_000_000);
    assert_eq!(TUNING.encrypted_preference_window_ns, 25_000_000);
}

#[test]
fn fields_keep_their_positions() {
    let mut fields = [0i64; 17];
    for (index, field) in fields.iter_mut().enumerate() {
        *field = index as i64 + 1;
    }
    let tuning = Tuning::from_fields(fields);
    assert_eq!(tuning.query_timeout_plain_ns, 1);
    assert_eq!(tuning.encrypted_preference_window_ns, 17);
    assert_eq!(tuning.fields(), fields);
}
