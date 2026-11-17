//! The desktop DNS data plane.
//!
//! `context` carries one query through the fixed pipeline; `pipeline` executes the stages in the
//! same order the Go service registered them; `listener` owns the UDP/TCP/DoT/DoH/DoQ sockets.

pub mod builder;
pub mod context;
pub mod pipeline;
pub mod server;
pub mod stages;
