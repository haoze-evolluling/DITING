//! The outbound proxy of the Android tunnel engine: SOCKS5 / HTTP CONNECT wire codecs, the
//! SOCKS5 UDP-associate framing and the config normalization.
//!
//! This crate is what is left of `android/engine/flow_outbound.go` once the sockets stay Go:
//!
//! * `config` - the normalized/validated proxy settings (protocol whitelist, loopback-only host,
//!   port range, 255-byte credentials, `all` / `apps` scope, positive UIDs) and its error texts.
//! * `socks5` - the greeting, the method/auth exchange, the request address encoding, the reply
//!   parser and the UDP datagram framing.
//! * `http` - the `CONNECT` request bytes (the reply is still read by Go's `http.ReadResponse`).
//! * `addr` - the Go `net` helpers those two need: `net.ParseIP`, `SplitHostPort`,
//!   `JoinHostPort` and `net.IP.String`.
//!
//! Everything here is pure: no socket, no clock, no logging. Go keeps dialing, deadlines, the
//! status channel and the error wrapping, and it keeps `net.Conn`/`net.PacketConn` types. The C ABI
//! in [`ffi`] is what `android/engine/proxy_native.go` loads with `dlopen`.
//!
//! A missing kernel is a hard failure for the proxy feature: `ConfigureOutboundProxy` reports it
//! instead of silently accepting a config nothing would enforce, and every dial through the proxy
//! reports the missing codec. Direct (non-proxy) traffic never touches this crate.

pub mod addr;
pub mod config;
pub mod ffi;
pub mod http;
pub mod payload;
pub mod socks5;
