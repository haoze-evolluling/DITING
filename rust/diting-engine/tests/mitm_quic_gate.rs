//! The full-tunnel UDP gate's half of the MITM contract: `setFilterHttp3` must drop UDP `:443` only
//! for the apps whose HTTPS traffic is being inspected, so their HTTP/3 falls back to TCP and the
//! MITM can see it. A separate test binary keeps the MITM integration file within its size budget.

mod support;

use std::sync::Arc;

use diting_engine::netstack::TcpKey;
use diting_engine::tunnel::gate::{admit_flow, FlowAction, FlowContext};
use diting_engine::Engine;
use support::wire::endpoint_v4;

const APP: &str = "com.test.app";
const UID: i32 = 10123;

fn scratch(label: &str) -> String {
    std::env::temp_dir()
        .join(format!(
            "diting-engine-quic-gate-{label}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map(|elapsed| elapsed.as_micros())
                .unwrap_or(0)
        ))
        .to_string_lossy()
        .into_owned()
}

#[test]
fn http3_is_dropped_only_for_the_inspected_apps() {
    let dir = scratch("quic-gate");
    let engine = Arc::new(Engine::new());
    let (pem, messages) = engine.mitm_state().start(&dir, &engine.upstream_trust());
    assert!(!pem.is_empty(), "MITM started: {messages:?}");
    let session = engine.mitm_state().session().expect("the session is live");
    assert_eq!(session.filter().set_allowed_uids_csv(&UID.to_string()), 1);
    engine.set_filter_http3(true);

    let app = endpoint_v4([10, 0, 0, 2], 40000);
    let quic = TcpKey::new(endpoint_v4([93, 184, 216, 34], 443), app);
    let inspected = FlowContext {
        uid: UID,
        app: APP.to_string(),
    };
    assert_eq!(
        admit_flow(&engine, false, &quic, &inspected),
        FlowAction::Blocked,
        "the inspected app's UDP :443 is dropped so HTTP/3 falls back to TCP"
    );
    let other = FlowContext {
        uid: UID + 1,
        app: "com.other.app".to_string(),
    };
    assert_eq!(
        admit_flow(&engine, false, &quic, &other),
        FlowAction::Relay,
        "an app that is not inspected keeps its QUIC"
    );

    engine.mitm_state().stop();
    let _ = std::fs::remove_dir_all(dir);
}
