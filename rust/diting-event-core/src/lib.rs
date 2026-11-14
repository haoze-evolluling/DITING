//! The unified event envelope and its one frozen schema (K9).
//!
//! Multiple entries (services, work manager, the automation receiver) publish state changes. To keep
//! external observers — Tasker, scripts, a future local HTTP API — from chasing a drifting JSON
//! shape, the envelope is defined and validated here, versioned with [`schema::SCHEMA_VERSION`],
//! and Kotlin builds it through the JNI bridge instead of assembling JSON by hand.
//!
//! Layout:
//! * [`schema`] — the frozen envelope, the `state_changed` builder and a validator.
//! * [`jni_bridge`] — the `com.haoze.diting.automation.EventNative` entry points.

pub mod jni_bridge;
pub mod schema;

pub use schema::{state_changed, validate, EVENT_STATE_CHANGED, SCHEMA_VERSION};
