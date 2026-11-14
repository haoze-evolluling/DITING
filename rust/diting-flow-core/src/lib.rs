//! The live connection (flow) table of the Android tunnel engine.
//!
//! One session is keyed by the 5-tuple plus the owning UID, so two apps dialing the same destination
//! stay separate rows. Bytes accrue, the domain label is filled from the sniffer / IP cache, and a
//! status tracks the lifecycle (active → closed / failed). Every mutation bumps a global sequence,
//! and [`FlowTable::snapshot`] returns only the sessions touched after a caller's cursor — that is
//! the "incremental snapshot" the UI polls, instead of resending the whole table each tick.
//!
//! There is no clock, no I/O and no logging: timestamps come in on the event, so the table is
//! deterministic and testable without sleeping. When the library is unavailable the engine simply
//! has no flow view; DNS answers are unaffected.

pub mod ffi;
pub mod payload;
pub mod session;

pub use session::{FlowEvent, FlowKey, FlowSession, FlowStatus, FlowTable, Snapshot};
