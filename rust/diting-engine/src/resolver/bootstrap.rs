//! The encrypted-DNS bootstrap dialer.
//!
//! `bootstrap_resolver.go` in Rust, with the scoring half left where it belongs: the endpoint health,
//! the weighted pick, the fallback order and the one-minute host cache are
//! [`diting_bootstrap_core::BootstrapKernel`]; this module owns the UDP queries, the racing loop, the
//! three-second budget per endpoint and the log line.
//!
//! Matching the Go resolver field by field:
//!
//! * the kernel keeps health keyed by endpoint id across a config change, and `update` only clears
//!   the host cache (`UpdateConfig`'s `clearCache`);
//! * a disabled or empty bootstrap returns the host unchanged, so the caller dials the provider
//!   hostname through the system resolver — that is what an engine configured without bootstrap
//!   does, and it is why server mode works without one;
//! * an IP literal never reaches the network (`net.ParseIP` fast path);
//! * each attempt is logged, `fallbackUsed` is true from the second endpoint on, and a successful
//!   exploration pick carries `exploration` as the message — the three fields
//!   `BootstrapLogWriter` renders;
//! * the A query is followed by an AAAA query only when the A answer carries no record.
//!
//! The kernel takes its two random rolls from the caller and never reads a clock, so both are
//! produced here from the clock and a counter (there is no `rand` dependency in this crate, and the
//! kernel only needs a uniform draw).

use std::net::IpAddr;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, RwLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use diting_bootstrap_core::BootstrapKernel;
use diting_dns_core::message::{extract, TYPE_A, TYPE_AAAA};
use diting_dns_wire::format_ipv4;
use tokio::net::UdpSocket;
use tokio::time::timeout;

use crate::config::BootstrapJson;
use crate::logs::{BootstrapEvent, BootstrapSink};
use crate::protect::ProtectorHandle;

/// `queryBootstrapDNS`'s budget: `context.WithTimeout(ctx, 3*time.Second)`.
pub const QUERY_TIMEOUT: Duration = Duration::from_secs(3);
/// The bootstrap port used when the configured IP carries none (`net.JoinHostPort(ip, "53")`).
pub const BOOTSTRAP_PORT: &str = "53";
/// The read buffer `queryBootstrapDNS` used.
const READ_BUFFER: usize = 2048;

/// One configured bootstrap endpoint.
#[derive(Debug, Clone, PartialEq)]
pub struct BootstrapIp {
    pub id: String,
    pub name: String,
    pub ip: String,
    pub weight: f64,
}

/// The published bootstrap configuration.
#[derive(Debug, Clone, Default)]
struct State {
    enabled: bool,
    ips: Vec<BootstrapIp>,
}

/// The engine's bootstrap resolver: one per engine, shared by every configured provider.
pub struct Bootstrap {
    state: RwLock<State>,
    kernel: BootstrapKernel,
    sink: Arc<dyn BootstrapSink>,
    /// The bootstrap queries are ordinary UDP sockets, so inside the VPN they need `protect` too:
    /// the configured resolver addresses are exactly the ones the TUN routes.
    protector: ProtectorHandle,
}

impl Bootstrap {
    pub fn new(sink: Arc<dyn BootstrapSink>) -> Self {
        Self::with_protector(sink, ProtectorHandle::new())
    }

    pub fn with_protector(sink: Arc<dyn BootstrapSink>, protector: ProtectorHandle) -> Self {
        Self {
            state: RwLock::new(State::default()),
            kernel: BootstrapKernel::new(),
            sink,
            protector,
        }
    }

    /// The engine installs the same handle the resolver dialers use, so one `setSocketProtector`
    /// covers the bootstrap queries and the four transports.
    pub fn protector(&self) -> ProtectorHandle {
        self.protector.clone()
    }

    /// `UpdateConfig`: publish the endpoints and drop the resolved-host cache. The health history is
    /// keyed by endpoint id and deliberately survives, exactly like the Go `healthMap`.
    pub fn update(&self, config: &BootstrapJson) {
        let ips: Vec<BootstrapIp> = config
            .ips
            .iter()
            .map(|entry| BootstrapIp {
                id: entry.id.clone(),
                name: entry.name.clone(),
                ip: entry.ip.clone(),
                weight: entry.weight,
            })
            .collect();
        {
            let mut state = self.write();
            state.enabled = config.enabled;
            state.ips = ips;
        }
        self.kernel.clear_cache();
    }

    /// `ResetStats`.
    pub fn reset(&self) {
        self.kernel.reset();
    }

    /// `IsEnabled`: enabled, configured and non-empty.
    pub fn is_enabled(&self) -> bool {
        let state = self.read();
        state.enabled && !state.ips.is_empty()
    }

    /// `ResolveHost`. `Ok(host)` whenever the caller should dial the configured hostname: a literal,
    /// or a disabled bootstrap. `Err` only when bootstrap is enabled and every endpoint failed.
    pub async fn resolve_host(&self, host: &str) -> Result<String, String> {
        if host.is_empty() {
            return Err("empty host".to_string());
        }
        if host.parse::<IpAddr>().is_ok() {
            return Ok(host.to_string());
        }

        let (enabled, ips) = {
            let state = self.read();
            (state.enabled, state.ips.clone())
        };
        if !enabled || ips.is_empty() {
            return Ok(host.to_string());
        }

        let normalized = host.trim().to_lowercase();
        if let Some(cached) = self.kernel.cache_get(&normalized, now_ns()) {
            return Ok(cached);
        }

        let plan = self.choose_plan(&ips);
        let Some(primary) = plan.primary else {
            return Ok(host.to_string());
        };
        if ips[primary].ip.is_empty() {
            return Err("no bootstrap IP configured".to_string());
        }

        let mut last_error: Option<String> = None;
        let mut order = Vec::with_capacity(1 + plan.fallbacks.len());
        order.push(primary);
        order.extend(plan.fallbacks.iter().copied());

        for (position, index) in order.iter().enumerate() {
            let entry = &ips[*index];
            let started = Instant::now();
            let fallback_used = position > 0;
            let outcome = query_endpoint(&entry.ip, &normalized, &self.protector).await;
            let mut elapsed_ms = started.elapsed().as_millis() as i64;
            if elapsed_ms < 1 {
                elapsed_ms = 1;
            }
            let success = matches!(&outcome, Ok(ip) if !ip.is_empty());
            self.kernel
                .record_result(&entry.id, success, elapsed_ms, now_ns());

            match outcome {
                Ok(ip) if !ip.is_empty() => {
                    self.kernel.cache_put(&normalized, &ip, now_ns());
                    self.sink.bootstrap(&BootstrapEvent {
                        ip_id: entry.id.clone(),
                        ip_name: entry.name.clone(),
                        ip: entry.ip.clone(),
                        host: normalized.clone(),
                        success: true,
                        elapsed_ms,
                        fallback_used,
                        error_message: if plan.exploration && position == 0 {
                            "exploration".to_string()
                        } else {
                            String::new()
                        },
                    });
                    return Ok(ip);
                }
                outcome => {
                    let message = outcome.err().unwrap_or_default();
                    self.sink.bootstrap(&BootstrapEvent {
                        ip_id: entry.id.clone(),
                        ip_name: entry.name.clone(),
                        ip: entry.ip.clone(),
                        host: normalized.clone(),
                        success: false,
                        elapsed_ms,
                        fallback_used,
                        error_message: message.clone(),
                    });
                    last_error = Some(message);
                }
            }
        }

        Err(match last_error {
            Some(error) => format!("bootstrap resolution failed for {host}: {error}"),
            None => format!("all bootstrap servers failed for {host}"),
        })
    }

    /// `choosePlan`: the kernel's primary plus its fallback order.
    fn choose_plan(&self, ips: &[BootstrapIp]) -> diting_bootstrap_core::Plan {
        if ips.is_empty() {
            return diting_bootstrap_core::Plan::default();
        }
        if ips.len() == 1 {
            return diting_bootstrap_core::Plan {
                primary: Some(0),
                fallbacks: Vec::new(),
                exploration: false,
            };
        }
        let entries: Vec<(String, f64)> = ips
            .iter()
            .map(|entry| (entry.id.clone(), entry.weight))
            .collect();
        self.kernel
            .plan(&entries, now_ns(), roll_f64(), roll_f64(), roll_u64())
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, State> {
        self.state.read().unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, State> {
        self.state
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

/// `queryBootstrapDNS`: one A query, then one AAAA query when the A answer had no record.
async fn query_endpoint(
    bootstrap_ip: &str,
    host: &str,
    protector: &ProtectorHandle,
) -> Result<String, String> {
    let text = if bootstrap_ip.parse::<IpAddr>().is_ok() {
        diting_upstream_core::endpoint::dial_address(bootstrap_ip, BOOTSTRAP_PORT, bootstrap_ip)
    } else {
        bootstrap_ip.to_string()
    };
    let target: std::net::SocketAddr = match text.parse() {
        Ok(address) => address,
        Err(_) => {
            // `net.SplitHostPort` succeeded in Go because it treats the whole text as the host;
            // join the default port the same way.
            let joined =
                diting_upstream_core::endpoint::dial_address(bootstrap_ip, BOOTSTRAP_PORT, "");
            joined
                .parse()
                .map_err(|_| format!("dial bootstrap {bootstrap_ip}: invalid address"))?
        }
    };

    let socket = crate::resolver::dial::bind_udp(target, protector)
        .and_then(UdpSocket::from_std)
        .map_err(|error| format!("dial bootstrap {}: {error}", target))?;
    socket
        .connect(target)
        .await
        .map_err(|error| format!("dial bootstrap {}: {error}", target))?;

    match exchange(&socket, host, TYPE_A).await? {
        Some(address) => Ok(address),
        None => match exchange(&socket, host, TYPE_AAAA).await? {
            Some(address) => Ok(address),
            None => Err(format!("no A/AAAA record for {host} from {target}")),
        },
    }
}

/// One query on the connected bootstrap socket. `None` means "no record of that type", which the
/// caller turns into the AAAA follow-up or the final error.
async fn exchange(socket: &UdpSocket, host: &str, qtype: u16) -> Result<Option<String>, String> {
    let query = crate::resolver::build_query(host, qtype);
    let mut buffer = vec![0u8; READ_BUFFER];
    // One deadline for the write and the read, like `conn.SetDeadline(deadline)`.
    let exchange_io = async {
        socket
            .send(&query)
            .await
            .map_err(|error| format!("write query to {}: {error}", peer_text(socket)))?;
        let read = socket
            .recv(&mut buffer)
            .await
            .map_err(|error| format!("read response from {}: {error}", peer_text(socket)))?;
        Ok::<usize, String>(read)
    };
    let read = match timeout(QUERY_TIMEOUT, exchange_io).await {
        Ok(result) => result?,
        Err(_) => {
            return Err(format!(
                "read response from {}: timed out",
                peer_text(socket)
            ))
        }
    };

    let Some(extracted) = extract(&buffer[..read]) else {
        return Err("unpack DNS response: invalid message".to_string());
    };
    for record in &extracted.addresses {
        match (qtype, record.address.len()) {
            (TYPE_A, 4) => return Ok(Some(format_ipv4(&record.address))),
            (TYPE_AAAA, 16) => return Ok(Some(diting_dns_wire::format_ipv6(&record.address))),
            _ => {}
        }
    }
    Ok(None)
}

fn peer_text(socket: &UdpSocket) -> String {
    socket
        .peer_addr()
        .map(|address| address.to_string())
        .unwrap_or_else(|_| "bootstrap".to_string())
}

/// A uniform `[0, 1)` draw for the kernel's exploration and weighted rolls.
fn roll_f64() -> f64 {
    // 53 bits is the mantissa of an f64, so the division is exact and the range is half-open.
    (roll_u64() >> 11) as f64 / (1u64 << 53) as f64
}

/// A 64-bit pseudo-random value: an xorshift over the clock and a counter, which is all the kernel
/// needs (it reduces the value modulo a small candidate count).
fn roll_u64() -> u64 {
    static COUNTER: AtomicU64 = AtomicU64::new(0x9e37_79b9_7f4a_7c15);
    let mut state = COUNTER.fetch_add(0x9e37_79b9_7f4a_7c15, Ordering::Relaxed)
        ^ SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|elapsed| elapsed.as_nanos() as u64)
            .unwrap_or(0);
    state ^= state << 13;
    state ^= state >> 7;
    state ^= state << 17;
    state
}

pub fn now_ns() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_nanos() as i64)
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::logs::EventSink;
    use std::sync::Mutex;

    #[derive(Default)]
    struct Recorder {
        events: Mutex<Vec<BootstrapEvent>>,
    }

    impl BootstrapSink for Recorder {
        fn bootstrap(&self, event: &BootstrapEvent) {
            self.events.lock().unwrap().push(event.clone());
        }
    }

    impl EventSink for Recorder {
        fn batch(&self, _json: &str) {}
        fn race(&self, _event: &crate::logs::RaceEvent) {}
        fn bootstrap(&self, event: &BootstrapEvent) {
            BootstrapSink::bootstrap(self, event);
        }
    }

    fn config(enabled: bool, ips: &[(&str, &str)]) -> BootstrapJson {
        BootstrapJson {
            enabled,
            ips: ips
                .iter()
                .map(|(id, ip)| crate::config::BootstrapIpJson {
                    id: id.to_string(),
                    name: id.to_string(),
                    ip: ip.to_string(),
                    weight: 1.0,
                })
                .collect(),
        }
    }

    #[tokio::test]
    async fn a_literal_never_reaches_the_network() {
        let recorder = Arc::new(Recorder::default());
        let bootstrap = Bootstrap::new(recorder.clone());
        bootstrap.update(&config(true, &[("a", "192.0.2.1")]));
        assert_eq!(
            bootstrap.resolve_host("1.1.1.1").await.expect("literal"),
            "1.1.1.1"
        );
        assert!(recorder.events.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn a_disabled_bootstrap_returns_the_hostname() {
        let bootstrap = Bootstrap::new(Arc::new(Recorder::default()));
        assert!(!bootstrap.is_enabled());
        assert_eq!(
            bootstrap.resolve_host("dns.example").await.expect("host"),
            "dns.example"
        );

        bootstrap.update(&config(false, &[("a", "192.0.2.1")]));
        assert!(!bootstrap.is_enabled());
        assert_eq!(
            bootstrap.resolve_host("dns.example").await.expect("host"),
            "dns.example"
        );
    }

    #[test]
    fn rolls_stay_in_range() {
        for _ in 0..1000 {
            let roll = roll_f64();
            assert!((0.0..1.0).contains(&roll), "{roll}");
        }
    }

    #[test]
    fn the_host_cache_is_cleared_by_a_config_change() {
        let bootstrap = Bootstrap::new(Arc::new(Recorder::default()));
        bootstrap.update(&config(true, &[("a", "192.0.2.1")]));
        bootstrap
            .kernel
            .cache_put("dns.example", "192.0.2.9", now_ns());
        assert_eq!(
            bootstrap
                .kernel
                .cache_get("dns.example", now_ns())
                .as_deref(),
            Some("192.0.2.9")
        );
        bootstrap.update(&config(true, &[("a", "192.0.2.1")]));
        assert!(bootstrap
            .kernel
            .cache_get("dns.example", now_ns())
            .is_none());
    }
}
