//! Member-list validation, cache keys and avatar acceptance rules. HTTP, disk cache and the avatar
//! bridge stay in Dart; this crate answers whether a document or an avatar is acceptable.

mod ffi;
mod members;
mod plan;

pub use members::parse_members;
pub use plan::plan;
