pub const DEFAULT_REQUEST_THRESHOLD: i64 = 5;
pub const DEFAULT_WINDOW_SECONDS: i64 = 60;
pub const DEFAULT_NXDOMAIN_SECONDS: i64 = 300;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DynamicBlock {
    pub enabled: bool,
    pub request_threshold: i64,
    pub window_seconds: i64,
    pub nxdomain_seconds: i64,
}

impl DynamicBlock {
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
