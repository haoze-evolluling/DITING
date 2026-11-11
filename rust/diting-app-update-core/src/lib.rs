//! Release checking: version comparison, `releases/latest` parsing, APK asset preference and the
//! HTTP status classification. HTTP, mirrors and every localized message stay in Dart.

mod ffi;
mod parse;
mod status;

pub use parse::{is_newer_version, parse_latest_release};
pub use status::status_message;
