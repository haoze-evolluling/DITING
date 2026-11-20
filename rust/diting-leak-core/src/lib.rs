pub mod evaluate;
pub mod ffi;

pub use evaluate::{evaluate, LeakStatus, Probe, Verdict};
pub use ffi::ABI_VERSION;
