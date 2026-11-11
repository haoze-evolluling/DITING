//! The transport tuning table.
//!
//! These were the `const` blocks of `resolver.go`, `resolver_plain.go`, `resolver_dot.go`,
//! `resolver_doq.go`, `resolver_smart.go` and the literals inside `buildDoHClient`. Keeping them in
//! one place means the four protocol files cannot drift, and the Go side reads the values once
//! through the ABI instead of holding a second copy.
//!
//! Field order is the payload order (`u8 layout | i64 ...`), so adding a field means bumping the
//! layout version on both sides.

/// Every transport constant, in nanoseconds unless the name says otherwise.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Tuning {
    /// `queryTimeoutPlain`: the budget for one plain UDP/TCP query.
    pub query_timeout_plain_ns: i64,
    /// `queryTimeoutDoH`.
    pub query_timeout_doh_ns: i64,
    /// `queryTimeoutDoT`.
    pub query_timeout_dot_ns: i64,
    /// `queryTimeoutDoQ`.
    pub query_timeout_doq_ns: i64,
    /// `connectTimeout`: the dial budget for every protocol.
    pub connect_timeout_ns: i64,
    /// How many UDP retries one plain query gets after the first read fails.
    pub plain_retry_limit: i64,
    /// `plainUDPRetryDelayFromContext`'s default when the caller supplied no adaptive value.
    pub plain_retry_default_ns: i64,
    /// The shorter budget used when probing a pooled DoT connection.
    pub dot_probe_timeout_ns: i64,
    /// `dotIdleTimeout`, in milliseconds (the pool is stamped in unix milliseconds).
    pub dot_idle_timeout_ms: i64,
    /// `dotMaxIdleConnsPerHost`.
    pub dot_max_idle_conns_per_host: i64,
    /// The read cap shared by the DoH body and the DoQ stream (`io.LimitReader`).
    pub max_read_bytes: i64,
    /// The pause before the one-shot DoH retry after an `EOF`.
    pub doh_retry_delay_ns: i64,
    /// `http.Transport.IdleConnTimeout` of the DoH client.
    pub doh_idle_conn_timeout_ns: i64,
    /// `http.Transport.MaxIdleConns`.
    pub doh_max_idle_conns: i64,
    /// `http.Transport.MaxIdleConnsPerHost`.
    pub doh_max_idle_conns_per_host: i64,
    /// `quic.Config.MaxIdleTimeout` of the DoQ session.
    pub doq_max_idle_timeout_ns: i64,
    /// `encryptedPreferenceWindow`: the grace period an in-flight DoH/DoT/DoQ query gets when a
    /// plain UDP upstream answers first in a mixed-protocol race.
    pub encrypted_preference_window_ns: i64,
}

/// The one copy of the table.
pub const TUNING: Tuning = Tuning {
    query_timeout_plain_ns: 5_000_000_000,
    query_timeout_doh_ns: 5_000_000_000,
    query_timeout_dot_ns: 5_000_000_000,
    query_timeout_doq_ns: 5_000_000_000,
    connect_timeout_ns: 3_000_000_000,
    plain_retry_limit: 2,
    plain_retry_default_ns: 1_500_000_000,
    dot_probe_timeout_ns: 2_000_000_000,
    dot_idle_timeout_ms: 15_000,
    dot_max_idle_conns_per_host: 4,
    max_read_bytes: 65_535,
    doh_retry_delay_ns: 10_000_000,
    doh_idle_conn_timeout_ns: 90_000_000_000,
    doh_max_idle_conns: 5,
    doh_max_idle_conns_per_host: 2,
    doq_max_idle_timeout_ns: 30_000_000_000,
    encrypted_preference_window_ns: 25_000_000,
};

impl Tuning {
    /// The fields in payload order.
    pub fn fields(&self) -> [i64; 17] {
        [
            self.query_timeout_plain_ns,
            self.query_timeout_doh_ns,
            self.query_timeout_dot_ns,
            self.query_timeout_doq_ns,
            self.connect_timeout_ns,
            self.plain_retry_limit,
            self.plain_retry_default_ns,
            self.dot_probe_timeout_ns,
            self.dot_idle_timeout_ms,
            self.dot_max_idle_conns_per_host,
            self.max_read_bytes,
            self.doh_retry_delay_ns,
            self.doh_idle_conn_timeout_ns,
            self.doh_max_idle_conns,
            self.doh_max_idle_conns_per_host,
            self.doq_max_idle_timeout_ns,
            self.encrypted_preference_window_ns,
        ]
    }

    /// Rebuilds the table from a payload body (no layout byte).
    pub fn from_fields(fields: [i64; 17]) -> Self {
        Self {
            query_timeout_plain_ns: fields[0],
            query_timeout_doh_ns: fields[1],
            query_timeout_dot_ns: fields[2],
            query_timeout_doq_ns: fields[3],
            connect_timeout_ns: fields[4],
            plain_retry_limit: fields[5],
            plain_retry_default_ns: fields[6],
            dot_probe_timeout_ns: fields[7],
            dot_idle_timeout_ms: fields[8],
            dot_max_idle_conns_per_host: fields[9],
            max_read_bytes: fields[10],
            doh_retry_delay_ns: fields[11],
            doh_idle_conn_timeout_ns: fields[12],
            doh_max_idle_conns: fields[13],
            doh_max_idle_conns_per_host: fields[14],
            doq_max_idle_timeout_ns: fields[15],
            encrypted_preference_window_ns: fields[16],
        }
    }
}

#[cfg(test)]
mod tests;
