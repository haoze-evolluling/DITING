//! Upstream endpoint targets: the `net.SplitHostPort` + default-port rule, and the dial address.
//!
//! Both resolvers opened with the same nine lines:
//!
//! ```text
//! host, port := server, "53"            // "853" for DoT
//! if h, p, err := net.SplitHostPort(server); err == nil { host, port = h, p }
//! targetHost := host
//! if bootstrap != nil && bootstrap.IsEnabled() {
//!     if resolvedIP, err := bootstrap.ResolveHost(ctx, host); err == nil && resolvedIP != "" {
//!         targetHost = resolvedIP
//!     }
//! }
//! targetServer := net.JoinHostPort(targetHost, port)
//! ```
//!
//! `SplitHostPort` / `JoinHostPort` keep Go's exact accept/reject sets through
//! `diting-go-compat::netaddr`, so a `dns.google:853` endpoint, a bare `dns.google`, a `[::1]:53`
//! literal and a non-numeric text port all split and join the way they used to. The bootstrap lookup
//! itself stays in Go (it is the encrypted-DNS bootstrap kernel plus a network query); only its
//! result is handed in here.

use diting_go_compat::netaddr::{join_host_port_text, split_host_port};

/// The protocols whose endpoint is a `host:port` string (DoH keeps its URL, DoQ is split by the
/// config kernel).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TargetProtocol {
    /// PLAIN (UDP port 53), also used for the TCP fallback and the explicit fallback server.
    Plain,
    /// DoT (TLS port 853).
    Dot,
}

impl TargetProtocol {
    /// The port used when `net.SplitHostPort` fails (which is what a bare host or an IPv6 literal
    /// without brackets does).
    pub fn default_port(self) -> &'static str {
        match self {
            TargetProtocol::Plain => "53",
            TargetProtocol::Dot => "853",
        }
    }
}

/// Splits one configured server into the host and port used for dialing.
pub fn split_target(server: &str, protocol: TargetProtocol) -> (String, String) {
    match split_host_port(server) {
        Ok((host, port)) => (host.to_string(), port.to_string()),
        // The Go code ignored the error and kept the whole server string as the host.
        Err(_) => (server.to_string(), protocol.default_port().to_string()),
    }
}

/// `net.JoinHostPort(targetHost, port)` with the bootstrapped address taking precedence when it is
/// non-empty.
pub fn dial_address(host: &str, port: &str, bootstrapped: &str) -> String {
    let target = if bootstrapped.is_empty() {
        host
    } else {
        bootstrapped
    };
    join_host_port_text(target, port)
}

#[cfg(test)]
mod tests;
