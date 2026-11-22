pub mod cert;
pub mod inject;
pub mod relay;
pub mod trust;
pub mod upstream;

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use http_body_util::combinators::UnsyncBoxBody;

pub type BoxError = Box<dyn std::error::Error + Send + Sync>;

pub type ResponseBody = UnsyncBoxBody<bytes::Bytes, BoxError>;

pub fn provider() -> Arc<rustls::crypto::CryptoProvider> {
    Arc::new(rustls::crypto::ring::default_provider())
}

pub fn now_unix() -> i64 {
    match SystemTime::now().duration_since(UNIX_EPOCH) {
        Ok(elapsed) => elapsed.as_secs() as i64,
        Err(_) => 0,
    }
}
