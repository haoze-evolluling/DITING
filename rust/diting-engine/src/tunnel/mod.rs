//! The TUN data plane: the `VpnService` descriptor, the transparent stack and the DNS flows.
//!
//! ```text
//! Kotlin VpnService                    diting-engine
//!   ParcelFileDescriptor.detachFd() ──► fd::TunFd (dup ×2, O_NONBLOCK)
//!                                          │
//!                          reader thread ──┴──► queue::Events
//!                                                   │
//!                                     stack thread ─┴──► netstack::Netstack (smoltcp)
//!                                                   │            │
//!                                     queue::Egress ◄┘            └─► dnsflow (tokio task)
//!                                          │                            │
//!                                writer thread ──► write(2)             └─► Events::Write
//! ```
//!
//! `UDP/TCP :53` inside the TUN is answered by [`crate::dns::serve_for_app`], everything else is
//! relayed by [`relay`] through the engine's outbound transport (direct, SOCKS5 or HTTP CONNECT, with
//! the per-UID proxy scope). `:853` is blocked when the setting is on, `UDP :443` is dropped when
//! HTTP/3 filtering is on (neither switch has a Kotlin caller yet — see the migration plan §4.3),
//! blocked UIDs are refused, and every flow is logged once with `connection` / `firewall:<reason>`.
//!
//! # What is deliberately not here
//!
//! * MITM (`StartStackMitm`): stage 4b. Without it the gate never returns `Intercept`, so a TLS flow
//!   is relayed end to end.
//! * The app allowlist and the MITM UID set: the gate is called with "allowed" / "not selected",
//!   which is what Go produced for express mode (no allowlist, nil MITM filter) and is the same for
//!   normal mode until the UI starts pushing an allowlist (`setAppAllowlist` has no caller).

pub mod dnsflow;
pub mod fd;
pub mod gate;
pub mod link;
pub mod queue;
pub mod relay;
pub mod session;
pub mod stats;
pub mod writeback;

pub use dnsflow::Inbound;
pub use fd::TunFd;
pub use link::{LinkFault, MemoryLink, PacketLink};
pub use session::Session;
pub use stats::TunnelCounters;
