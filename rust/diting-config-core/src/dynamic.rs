//! The dynamic-block defaults.
//!
//! `ApplyDNSConfig` filled in three values before anything else looked at the config: a request
//! threshold of 5, a window of 60 seconds and an NXDOMAIN hold of 300 seconds, each used when the
//! incoming value was not positive. The numbers live here so the kernel that counts requests and the
//! config that describes them share one set.

/// Default request threshold: the fifth request inside the window escalates the answer.
pub const DEFAULT_REQUEST_THRESHOLD: i64 = 5;
/// Default window length, in seconds.
pub const DEFAULT_WINDOW_SECONDS: i64 = 60;
/// Default NXDOMAIN hold, in seconds.
pub const DEFAULT_NXDOMAIN_SECONDS: i64 = 300;

/// One dynamic-block config, already normalized.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DynamicBlock {
    pub enabled: bool,
    pub request_threshold: i64,
    pub window_seconds: i64,
    pub nxdomain_seconds: i64,
}

impl DynamicBlock {
    /// Applies the `< 1` defaults, exactly like `ApplyDNSConfig` did.
    pub fn normalized(
        enabled: bool,
        request_threshold: i64,
        window_seconds: i64,
        nxdomain_seconds: i64,
    ) -> Self {
        Self {
            enabled,
            request_threshold: if request_threshold < 1 {
                DEFAULT_REQUEST_THRESHOLD
            } else {
                request_threshold
            },
            window_seconds: if window_seconds < 1 {
                DEFAULT_WINDOW_SECONDS
            } else {
                window_seconds
            },
            nxdomain_seconds: if nxdomain_seconds < 1 {
                DEFAULT_NXDOMAIN_SECONDS
            } else {
                nxdomain_seconds
            },
        }
    }
}

#[cfg(test)]
mod tests;
