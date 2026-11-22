mod ffi;
mod parse;
mod status;

pub use parse::{is_newer_version, parse_latest_release};
pub use status::status_message;
