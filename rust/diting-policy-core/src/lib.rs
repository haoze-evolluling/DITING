pub mod cache;
pub mod decision;
pub mod dtri_read;
pub mod ffi;
pub mod glob;
pub mod json;
pub mod route;
pub mod snapshot;
pub mod special;
pub mod tables;
pub mod wildcard_index;

pub use diting_go_compat::dns_type;
pub use diting_go_compat::regex as regex_go;
pub use diting_go_compat::text;

pub use cache::Reason;
pub use decision::Decision;
pub use ffi::ABI_VERSION;
pub use route::{evaluate as evaluate_route, MatchKind, RouteDecision, RouteRule};
pub use snapshot::{Answer, Snapshot};
