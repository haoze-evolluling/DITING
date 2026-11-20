pub mod ffi;
pub mod host;
pub mod inject;
pub mod local;
pub mod payload;
pub mod rules;

pub use host::{link_tag, normalize_host, query_escape};
pub use inject::{Injector, Outcome, Upstream, HEAD_TAG, SCAN_LIMIT};
pub use local::{is_asset_host, respond, Response};
pub use rules::{host_suffixes, DomainRules, RuleSet, Rules};
