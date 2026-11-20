pub mod alt_svc;
pub mod doh;
pub mod endpoint;
pub mod ffi;
pub mod framing;
pub mod payload;
pub mod plan;
pub mod pool;
pub mod tuning;

pub use doh::{should_retry, status_kind, StatusKind};
pub use endpoint::{dial_address, split_target, TargetProtocol};
pub use framing::{
    doq_skip, dot_response_length, encode_length_prefixed, is_truncated, tcp_response_length,
    DotLength,
};
pub use plan::{is_policy_rejection, strategy, Strategy};
pub use pool::{Acquired, DotPool};
pub use tuning::{Tuning, TUNING};
