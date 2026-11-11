//! Rust core for the Android AI-analysis assistant: clipboard recognition, the legacy key
//! obfuscator, prompt building, the traffic summary behind the prompt, and the OpenAI-compatible
//! protocol layer.
//!
//! This is the only implementation. `RustAgentCore.instance` loads the library at runtime and
//! throws when the artifact is missing or its ABI version differs, so a build that forgot
//! `python rust/build_android.py` fails on the first call instead of quietly running a second copy
//! of the semantics.
//!
//! The HTTP transport and the localised sentences stay in Dart: closing a socket is the only way to
//! abort a pending read, and user-facing text belongs with the app's localisation.
//!
//! Layout:
//! * [`paste`] — the four-step clipboard recogniser (`agent_api_text_parser.dart`).
//! * [`secret`] — the XOR-mask + Base64 key obfuscator (`key_obfuscator.dart`).
//! * [`prompt`] — the two analysis prompts (`agent_prompts.dart`).
//! * [`traffic`] — log-table aggregation and the rendered section (`agent_traffic_summary.dart`).
//! * [`api`] — endpoint derivation, request body and both response shapes (`agent_api_client.dart`).
//! * [`wire`] — the little-endian payload reader/writer.
//! * [`payload`] — the traffic-summary block shared by two entries.
//! * [`ffi`] — the C ABI surface.

pub mod api;
pub mod ffi;
pub mod paste;
pub mod payload;
pub mod prompt;
pub mod secret;
pub mod traffic;
pub mod wire;

pub use api::{
    chat_body, chat_endpoint, describe_status, models_endpoint, parse_chat, parse_models,
};
pub use ffi::ABI_VERSION;
pub use paste::{parse as parse_paste, PasteKind, PasteResult};
pub use prompt::{domain_request, traffic_request, AnalysisRequest};
pub use secret::{open as open_api_key, seal as seal_api_key};
pub use traffic::{summarize, DnsRow, Summary};
