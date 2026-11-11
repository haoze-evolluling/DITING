use super::*;

fn input(port: u16, ip: &[u8]) -> FlowInput<'_> {
    FlowInput {
        port,
        ip,
        app_allowlist_allowed: true,
        ..FlowInput::default()
    }
}

const PUBLIC: [u8; 4] = [93, 184, 216, 34];

#[test]
fn full_udp_order() {
    // Blocked UID wins over everything, without a connection log.
    let mut flow = input(PORT_DNS, &PUBLIC);
    flow.uid_blocked = true;
    let decision = admit(MODE_FULL_UDP, &flow);
    assert_eq!(decision.action, ACTION_BLOCK_UID);
    assert!(!decision.log_connection);

    // Port 53 is handled before the encrypted-DNS and allowlist gates, without a log.
    let mut flow = input(PORT_DNS, &PUBLIC);
    flow.encrypted_dns_blocked = true;
    flow.app_allowlist_allowed = false;
    let decision = admit(MODE_FULL_UDP, &flow);
    assert_eq!(decision.action, ACTION_HANDLE_DNS);
    assert!(!decision.log_connection);

    // Encrypted DNS before the allowlist, still no log.
    let mut flow = input(853, &PUBLIC);
    flow.encrypted_dns_blocked = true;
    flow.app_allowlist_allowed = false;
    let decision = admit(MODE_FULL_UDP, &flow);
    assert_eq!(decision.action, ACTION_BLOCK_ENCRYPTED_DNS);
    assert!(!decision.log_connection);

    let mut flow = input(443, &PUBLIC);
    flow.app_allowlist_allowed = false;
    assert_eq!(
        admit(MODE_FULL_UDP, &flow).action,
        ACTION_BLOCK_APP_ALLOWLIST
    );

    // A QUIC block logs the connection first.
    let mut flow = input(443, &PUBLIC);
    flow.quic_drop = true;
    flow.quic_uid_selected = true;
    let decision = admit(MODE_FULL_UDP, &flow);
    assert_eq!(decision.action, ACTION_BLOCK_QUIC);
    assert!(decision.log_connection);

    // A QUIC block only applies to port 443.
    let mut flow = input(8443, &PUBLIC);
    flow.quic_drop = true;
    flow.quic_uid_selected = true;
    assert_eq!(admit(MODE_FULL_UDP, &flow).action, ACTION_RELAY);

    let decision = admit(MODE_FULL_UDP, &input(443, &PUBLIC));
    assert_eq!(decision.action, ACTION_RELAY);
    assert!(decision.log_connection);
}

#[test]
fn full_tcp_order() {
    let mut flow = input(853, &PUBLIC);
    flow.uid_blocked = true;
    assert_eq!(admit(MODE_FULL_TCP, &flow).action, ACTION_BLOCK_UID);

    let mut flow = input(PORT_DNS, &PUBLIC);
    flow.app_allowlist_allowed = false;
    let decision = admit(MODE_FULL_TCP, &flow);
    assert_eq!(decision.action, ACTION_BLOCK_APP_ALLOWLIST);
    assert!(!decision.log_connection);

    // Port 53 comes before encrypted DNS, and neither is logged on this path.
    let mut flow = input(PORT_DNS, &PUBLIC);
    flow.encrypted_dns_blocked = true;
    let decision = admit(MODE_FULL_TCP, &flow);
    assert_eq!(decision.action, ACTION_HANDLE_DNS);
    assert!(!decision.log_connection);

    let mut flow = input(853, &PUBLIC);
    flow.encrypted_dns_blocked = true;
    let decision = admit(MODE_FULL_TCP, &flow);
    assert_eq!(decision.action, ACTION_BLOCK_ENCRYPTED_DNS);
    assert!(!decision.log_connection);

    let decision = admit(MODE_FULL_TCP, &input(443, &PUBLIC));
    assert_eq!(decision.action, ACTION_RELAY);
    assert!(decision.log_connection);
}

#[test]
fn mitm_tcp_order() {
    let mut flow = input(443, &PUBLIC);
    flow.uid_blocked = true;
    assert_eq!(admit(MODE_MITM_TCP, &flow).action, ACTION_BLOCK_UID);

    let mut flow = input(443, &PUBLIC);
    flow.app_allowlist_allowed = false;
    assert_eq!(
        admit(MODE_MITM_TCP, &flow).action,
        ACTION_BLOCK_APP_ALLOWLIST
    );

    // An unspecified address is dropped before anything is logged.
    let unspecified = [0u8; 4];
    let decision = admit(MODE_MITM_TCP, &input(443, &unspecified));
    assert_eq!(decision.action, ACTION_DROP_UNSPECIFIED);
    assert!(!decision.log_connection);

    // Encrypted DNS is blocked after the log point and before port 53.
    let mut flow = input(853, &PUBLIC);
    flow.encrypted_dns_blocked = true;
    let decision = admit(MODE_MITM_TCP, &flow);
    assert_eq!(decision.action, ACTION_BLOCK_ENCRYPTED_DNS);
    assert!(decision.log_connection);

    let decision = admit(MODE_MITM_TCP, &input(PORT_DNS, &PUBLIC));
    assert_eq!(decision.action, ACTION_HANDLE_DNS);
    assert!(decision.log_connection);

    // Loopback/private and non-80/443 flows bypass interception.
    let loopback = [127, 0, 0, 1];
    assert_eq!(
        admit(MODE_MITM_TCP, &input(443, &loopback)).action,
        ACTION_RELAY
    );
    assert_eq!(
        admit(MODE_MITM_TCP, &input(8080, &PUBLIC)).action,
        ACTION_RELAY
    );

    let mut flow = input(443, &PUBLIC);
    flow.mitm_uid_allowed = false;
    assert_eq!(admit(MODE_MITM_TCP, &flow).action, ACTION_RELAY);

    let mut flow = input(443, &PUBLIC);
    flow.mitm_uid_allowed = true;
    let decision = admit(MODE_MITM_TCP, &flow);
    assert_eq!(decision.action, ACTION_INTERCEPT);
    assert!(decision.log_connection);

    // HTTP is intercepted too.
    let mut flow = input(80, &PUBLIC);
    flow.mitm_uid_allowed = true;
    assert_eq!(admit(MODE_MITM_TCP, &flow).action, ACTION_INTERCEPT);
}

#[test]
fn decision_packs_and_unpacks_the_log_bit() {
    let decision = Decision::new(ACTION_RELAY, true);
    assert_eq!(Decision::from_u32(decision.to_u32()), decision);
    let quiet = Decision::new(ACTION_BLOCK_UID, false);
    assert_eq!(Decision::from_u32(quiet.to_u32()), quiet);
}
