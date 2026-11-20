pub mod evaluate;
pub mod ffi;

pub use evaluate::{
    evaluate, gate, parse_portal_url, GateDecision, PortalState, PortalVerdict, Probe,
};
pub use ffi::ABI_VERSION;
