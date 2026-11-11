use super::*;

const T0: i64 = 1_700_000_000_000_000_000;

fn v4(a: u8, b: u8, c: u8, d: u8) -> Vec<u8> {
    vec![a, b, c, d]
}

fn entries(pairs: &[(i32, &[&str])]) -> Vec<(i32, Vec<String>)> {
    pairs
        .iter()
        .map(|(uid, domains)| (*uid, domains.iter().map(|d| (*d).to_string()).collect()))
        .collect()
}

#[test]
fn a_configured_uid_only_resolves_its_own_domains() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[(1, &["example.com"])]));

    assert!(kernel.has_uids());
    assert!(kernel.domain_allowed(1, "example.com"));
    assert!(kernel.domain_allowed(1, "www.example.com"));
    assert!(!kernel.domain_allowed(1, "other.example"));
    // An unselected UID is not restricted at all.
    assert!(kernel.domain_allowed(2, "other.example"));
}

#[test]
fn a_selected_uid_with_an_empty_set_may_resolve_nothing() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[(7, &[])]));

    assert!(kernel.has_uids());
    assert!(!kernel.domain_allowed(7, "example.com"));
    assert!(!kernel.connection_allowed(7, &v4(203, 0, 113, 7), T0));
    // Loopback stays reachable even for a selected UID.
    assert!(kernel.connection_allowed(7, &v4(127, 0, 0, 1), T0));
}

#[test]
fn loopback_and_unselected_uids_connect_freely() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[(1, &["example.com"])]));

    assert!(kernel.connection_allowed(1, &v4(127, 0, 0, 1), T0));
    assert!(kernel.connection_allowed(1, &[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], T0));
    assert!(kernel.connection_allowed(2, &v4(203, 0, 113, 7), T0));
    assert!(!kernel.connection_allowed(1, &v4(203, 0, 113, 7), T0));
}

#[test]
fn a_positive_answer_grants_the_matching_uids_until_the_ttl() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[
        (1, &["example.com"]),
        (2, &["example.com"]),
        (3, &["other.example"]),
    ]));

    let records = vec![(v4(203, 0, 113, 7), 300)];
    kernel.remember(0, "sub.example.com.", &records, T0);

    assert!(kernel.connection_allowed(1, &v4(203, 0, 113, 7), T0));
    assert!(kernel.connection_allowed(2, &v4(203, 0, 113, 7), T0));
    assert!(!kernel.connection_allowed(3, &v4(203, 0, 113, 7), T0));

    let expiry = T0 + 300 * 1_000_000_000;
    assert!(kernel.connection_allowed(1, &v4(203, 0, 113, 7), expiry - 1));
    assert!(!kernel.connection_allowed(1, &v4(203, 0, 113, 7), expiry));
    assert_eq!(kernel.grant_count(1), 1);
    assert_eq!(kernel.grant_count(2), 1);
    assert_eq!(kernel.grant_count(3), 0);
}

#[test]
fn an_answer_without_a_question_only_grants_its_owner() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[(1, &["example.com"]), (2, &["example.com"])]));

    kernel.remember(1, "", &[(v4(203, 0, 113, 8), 60)], T0);

    assert!(kernel.connection_allowed(1, &v4(203, 0, 113, 8), T0));
    assert!(!kernel.connection_allowed(2, &v4(203, 0, 113, 8), T0));
}

#[test]
fn zero_ttl_unspecified_and_empty_records_never_grant() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[(1, &["example.com"])]));

    let records = vec![
        (v4(203, 0, 113, 7), 0),
        (v4(0, 0, 0, 0), 300),
        (vec![0u8; 16], 300),
        // The IPv4-mapped zero form is `net.IPv4zero` to Go as well.
        (
            vec![0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff, 0, 0, 0, 0],
            300,
        ),
        (Vec::new(), 300),
    ];
    kernel.remember(1, "example.com.", &records, T0);

    assert_eq!(kernel.grant_count(1), 0);
    assert!(!kernel.connection_allowed(1, &v4(203, 0, 113, 7), T0));
}

#[test]
fn a_mismatched_question_grants_nothing() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[(1, &["example.com"])]));

    kernel.remember(1, "elsewhere.example.", &[(v4(203, 0, 113, 7), 60)], T0);
    assert_eq!(kernel.grant_count(1), 0);
}

#[test]
fn duplicate_config_entries_use_the_last_set() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[
        (1, &["first.example"]),
        (1, &["second.example"]),
    ]));

    assert!(!kernel.domain_allowed(1, "first.example"));
    assert!(kernel.domain_allowed(1, "second.example"));
}

#[test]
fn reconfiguring_drops_every_existing_grant() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[(1, &["example.com"])]));
    kernel.remember(1, "example.com.", &[(v4(203, 0, 113, 7), 300)], T0);
    assert!(kernel.connection_allowed(1, &v4(203, 0, 113, 7), T0));

    kernel.configure(&entries(&[(1, &["example.com"])]));
    assert!(!kernel.connection_allowed(1, &v4(203, 0, 113, 7), T0));
    assert_eq!(kernel.grant_count(1), 0);
}

#[test]
fn exceeding_256_grants_prunes_the_expired_ones() {
    let kernel = AllowlistKernel::new();
    kernel.configure(&entries(&[(1, &["example.com"])]));

    let first_batch: Vec<(Vec<u8>, u32)> =
        (0..=255).map(|index| (vec![10, 0, 0, index], 1)).collect();
    kernel.remember(1, "example.com.", &first_batch, T0);
    assert_eq!(kernel.grant_count(1), MAX_GRANTS as u32);

    // Two seconds later the first 256 grants are expired; inserting a 257th triggers the prune.
    let later = T0 + 2_000_000_000;
    kernel.remember(1, "example.com.", &[(vec![10, 0, 1, 0], 300)], later);

    assert_eq!(kernel.grant_count(1), 1);
    assert!(kernel.connection_allowed(1, &[10, 0, 1, 0], later));
    assert!(!kernel.connection_allowed(1, &[10, 0, 0, 1], later));
}
