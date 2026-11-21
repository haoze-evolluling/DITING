#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Tuning {
    pub query_timeout_plain_ns: i64,
    pub query_timeout_doh_ns: i64,
    pub query_timeout_dot_ns: i64,
    pub connect_timeout_ns: i64,
    pub plain_retry_limit: i64,
    pub plain_retry_default_ns: i64,
    pub dot_probe_timeout_ns: i64,
    pub dot_idle_timeout_ms: i64,
    pub dot_max_idle_conns_per_host: i64,
    pub max_read_bytes: i64,
    pub doh_retry_delay_ns: i64,
    pub doh_idle_conn_timeout_ns: i64,
    pub doh_max_idle_conns: i64,
    pub doh_max_idle_conns_per_host: i64,
    pub encrypted_preference_window_ns: i64,
}

pub const TUNING: Tuning = Tuning {
    query_timeout_plain_ns: 5_000_000_000,
    query_timeout_doh_ns: 5_000_000_000,
    query_timeout_dot_ns: 5_000_000_000,
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
    encrypted_preference_window_ns: 25_000_000,
};

impl Tuning {
    pub fn fields(&self) -> [i64; 15] {
        [
            self.query_timeout_plain_ns,
            self.query_timeout_doh_ns,
            self.query_timeout_dot_ns,
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
            self.encrypted_preference_window_ns,
        ]
    }

    pub fn from_fields(fields: [i64; 15]) -> Self {
        Self {
            query_timeout_plain_ns: fields[0],
            query_timeout_doh_ns: fields[1],
            query_timeout_dot_ns: fields[2],
            connect_timeout_ns: fields[3],
            plain_retry_limit: fields[4],
            plain_retry_default_ns: fields[5],
            dot_probe_timeout_ns: fields[6],
            dot_idle_timeout_ms: fields[7],
            dot_max_idle_conns_per_host: fields[8],
            max_read_bytes: fields[9],
            doh_retry_delay_ns: fields[10],
            doh_idle_conn_timeout_ns: fields[11],
            doh_max_idle_conns: fields[12],
            doh_max_idle_conns_per_host: fields[13],
            encrypted_preference_window_ns: fields[14],
        }
    }
}

#[cfg(test)]
mod tests;
