//! Stage 0 spike: can `smoltcp` transparently proxy the traffic a TUN device delivers?
//!
//! The Go engine gets this for free from gVisor: the sentry accepts a connection to *any*
//! destination address and port because the whole stack is per-packet, not per-listener. This was
//! the highest risk of the migration — the one question that could invalidate the schedule — so this
//! crate answers it before any production code is written.
//!
//! The shape being tested is the one the engine will use:
//!
//! * one `Interface` with [`smoltcp::iface::Interface::set_any_ip`] so packets for addresses the
//!   interface was never configured with are not dropped on ingress;
//! * one `tcp::Socket` per flow, created on the client's SYN and bound to the *original*
//!   destination endpoint, so the SYN-ACK leaves with the destination address as its source;
//! * one `udp::Socket` per destination port, bound to any address, using
//!   [`smoltcp::socket::udp::UdpMetadata::local_address`] to recover the original destination for
//!   every datagram;
//! * bounded flow tables, per-flow byte caps and idle expiry, because the engine has no GC to fall
//!   back on.
//!
//! What is *not* here, and stays in the engine: the TUN read/write threads, the `poll` timer and
//! `poll_at` deadline, the `AsyncRead`/`AsyncWrite` adapters and their wakers, the QUIC / encrypted
//! DNS drop policy, `protect` on the outbound sockets, and the tokio task that owns the stack. The
//! spike drives the stack from a synchronous loop instead of an actor.
//!
//! `tests/transparent_tcp.rs` and `tests/transparent_udp.rs` are the evidence: hand-crafted client
//! packets (no second stack, no privileges, no device) go in, real segments come out.

pub mod device;
pub mod flow;
pub mod stack;
pub mod wire;

pub use flow::{Stats, TcpFlow, TcpKey, UdpDatagram};
pub use stack::{Limits, Netstack};
