//! N9: the LAN client rate limiter installed on the engine actually gates clients.

use diting_engine::Engine;
use diting_ratelimit_core::{Addr, Config};

#[test]
fn a_disabled_limiter_lets_every_client_through() {
    let engine = Engine::new();
    let addr = Addr::from_bytes(&[192, 0, 2, 1]).expect("ipv4");
    assert!(engine.allow_client(Some(&addr), 0));
    assert!(engine.allow_client(None, 0));
}

#[test]
fn an_installed_limiter_enforces_the_burst() {
    let engine = Engine::new();
    let addr = Addr::from_bytes(&[192, 0, 2, 1]).expect("ipv4");
    let config = Config {
        enabled: true,
        rate: 1.0,
        burst: 1,
        ..Config::default()
    };
    engine.set_rate_limit(&config);
    assert!(engine.allow_client(Some(&addr), 0), "first packet fits the burst");
    assert!(
        !engine.allow_client(Some(&addr), 0),
        "a second packet at the same instant exceeds burst 1"
    );
}

#[test]
fn disabling_again_clears_the_limiter() {
    let engine = Engine::new();
    let addr = Addr::from_bytes(&[0x20, 0x01, 0x0d, 0xb8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1])
        .expect("ipv6");
    engine.set_rate_limit(&Config {
        enabled: true,
        rate: 1.0,
        burst: 1,
        ..Config::default()
    });
    assert!(engine.allow_client(Some(&addr), 0));
    assert!(!engine.allow_client(Some(&addr), 0));
    engine.set_rate_limit(&Config::default());
    assert!(engine.allow_client(Some(&addr), 0), "a disabled config clears the limiter");
}
