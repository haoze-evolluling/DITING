//! IP-quality checking for the Android tools page.
//!
//! The Dart caller keeps every HTTP request, timeout and socket; this crate owns everything that
//! reads an answer:
//!
//! * [`probe`] - the "what is my egress IP" body (plain text or `{"ip": "..."}`) and the
//!   IP-shaped gate.
//! * [`source`] - the three public IP-intelligence replies (`ip-api.com`, `ipwho.is`,
//!   `ipinfo.io`), their status tokens, organization/ASN extraction and the keyword classifier.
//! * [`summary`] - the report: majority IP type with the severity tie-break, the level and the
//!   first non-empty organization/ASN.
//! * [`ffi`] - the JSON entry the Flutter app loads over `dart:ffi`.
//!
//! There is no Dart copy left to fall back to: a missing library rejects the check instead of
//! producing a second classification with different keywords.

mod ffi;
mod probe;
mod source;
mod summary;

pub use probe::{is_ip_like, parse_probe};
pub use source::{source_result, Source};
pub use summary::summarize;
