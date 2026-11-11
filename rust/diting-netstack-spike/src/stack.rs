//! The transparent-proxy stack: the piece gVisor used to provide.
//!
//! # The question the spike answers
//!
//! gVisor accepts any destination because it has no listener table at all: every packet that
//! arrives on the TUN is matched against a connection, and a new one is born on the SYN. `smoltcp`
//! is the opposite by default: an interface drops ingress packets whose destination is not one of
//! its configured addresses, and a TCP socket only takes SYNs for its own listening endpoint.
//!
//! Two knobs close the gap, and both are supported by `smoltcp` 0.14:
//!
//! 1. [`Interface::set_any_ip(true)`](smoltcp::iface::Interface::set_any_ip) makes
//!    `InterfaceInner::has_ip_addr` return `true` unconditionally, so ingress for any destination
//!    address reaches the socket layer. IPv4 and IPv6 both go through that check.
//! 2. A `tcp::Socket` trained with `listen()` on a *fully specified* endpoint accepts SYNs for that
//!    endpoint only, which is exactly what the engine wants: create one socket per SYN, bound to
//!    the destination address and port the client asked for. The SYN-ACK then leaves with the
//!    destination as its source address, and the TCP tuple keeps the original destination, so no
//!    NAT bookkeeping is needed on the way out.
//!
//! UDP needs less: `bind()` to a port with no address accepts datagrams for every destination,
//! and `UdpMetadata::local_address` reports the address the datagram was actually sent to. One
//! socket per destination *port* therefore serves every destination address, and the reply only has
//! to name `local_address` again.
//!
//! # What the engine adds on top
//!
//! The spike stops at "packets in, packets out". The engine still owns the TUN threads, the
//! `poll_at` timer, the async adapters that give each flow an `AsyncRead`/`AsyncWrite` pair with
//! wakers, the QUIC drop (`UDP 443`) and encrypted-DNS block (`TCP/UDP 853`) policies, the
//! `protect` call before any outbound connect, and the tokio task that owns this struct behind a
//! mutex. The bounds in [`Limits`] are the ones that matter there, so they are already enforced
//! here.

use std::collections::{BTreeMap, VecDeque};

use smoltcp::iface::{Config as IfaceConfig, Interface, SocketSet};
use smoltcp::socket::{tcp, udp};
use smoltcp::time::{Duration, Instant};
use smoltcp::wire::{
    HardwareAddress, IpAddress, IpCidr, IpEndpoint, IpListenEndpoint, IpProtocol, IpVersion,
    Ipv4Packet, Ipv6Packet, TcpControl, TcpPacket, TcpRepr, UdpPacket, UdpRepr,
};

use crate::device::IpDevice;
use crate::flow::{Stats, TcpFlow, TcpKey, UdpBinding, UdpDatagram};

/// The resource bounds from section 5.2 of the migration plan.
#[derive(Clone, Copy, Debug)]
pub struct Limits {
    /// TUN MTU. Android uses 1400 so that the VPN's own headers still fit the carrier MTU.
    pub mtu: usize,
    /// Hard caps on the two flow tables; a SYN or a first datagram past the cap is dropped.
    pub max_tcp_flows: usize,
    pub max_udp_bindings: usize,
    /// Per-socket smoltcp buffers. These are allocated when the flow is created.
    pub tcp_rx_bytes: usize,
    pub tcp_tx_bytes: usize,
    pub udp_rx_bytes: usize,
    pub udp_tx_bytes: usize,
    /// Cap on the bytes buffered for the relay loop in one flow, and the number of packet slots in
    /// one UDP binding. Overflow aborts the flow rather than growing the heap: there is no GC.
    pub flow_buffer_bytes: usize,
    pub udp_slots: usize,
    /// Idle TCP flows are torn down after this long, mirroring `set_timeout`.
    pub tcp_idle: Duration,
    /// Keepalive interval, mirroring the Go engine's `28 * time.Second`.
    pub keepalive: Option<Duration>,
}

impl Default for Limits {
    fn default() -> Self {
        Self {
            mtu: 1400,
            max_tcp_flows: 4096,
            max_udp_bindings: 2048,
            tcp_rx_bytes: 32 * 1024,
            tcp_tx_bytes: 32 * 1024,
            udp_rx_bytes: 4096,
            udp_tx_bytes: 4096,
            flow_buffer_bytes: 128 * 1024,
            udp_slots: 32,
            tcp_idle: Duration::from_secs(300),
            keepalive: Some(Duration::from_secs(28)),
        }
    }
}

pub struct Netstack {
    device: IpDevice,
    iface: Interface,
    sockets: SocketSet<'static>,
    limits: Limits,
    tcp: BTreeMap<TcpKey, TcpFlow>,
    udp: BTreeMap<u16, UdpBinding>,
    datagrams: VecDeque<UdpDatagram>,
    stats: Stats,
}

impl Netstack {
    /// Build the stack. The configured address is the unspecified address on purpose: with
    /// `any_ip` the socket layer ignores it, and using a real address here would hide a missing
    /// `set_any_ip` behind a passing test.
    pub fn new(limits: Limits) -> Self {
        let mut device = IpDevice::new(limits.mtu);
        let mut iface = Interface::new(
            IfaceConfig::new(HardwareAddress::Ip),
            &mut device,
            Instant::ZERO,
        );
        iface.set_any_ip(true);
        iface.update_ip_addrs(|addrs| {
            addrs
                .push(IpCidr::new(IpAddress::v4(0, 0, 0, 0), 0))
                .expect("the address list has room for two entries");
            addrs
                .push(IpCidr::new(IpAddress::v6(0, 0, 0, 0, 0, 0, 0, 0), 0))
                .expect("the address list has room for two entries");
        });

        Self {
            device,
            iface,
            sockets: SocketSet::new(Vec::new()),
            limits,
            tcp: BTreeMap::new(),
            udp: BTreeMap::new(),
            datagrams: VecDeque::new(),
            stats: Stats::default(),
        }
    }

    pub fn limits(&self) -> Limits {
        self.limits
    }

    pub fn stats(&self) -> Stats {
        self.stats
    }

    /// Hand one packet, exactly as read from the TUN fd, to the stack. The stack is polled for as
    /// long as it has work, so the caller only has to drain [`Netstack::egress`] afterwards.
    pub fn ingress(&mut self, packet: &[u8], now: Instant) {
        self.stats.packets_in += 1;
        self.stats.bytes_in += packet.len() as u64;

        let Ok(version) = IpVersion::of_packet(packet) else {
            self.stats.malformed += 1;
            return;
        };

        match version {
            IpVersion::Ipv4 => {
                let Ok(ipv4) = Ipv4Packet::new_checked(packet) else {
                    self.stats.malformed += 1;
                    return;
                };
                let src = IpAddress::Ipv4(ipv4.src_addr());
                let dst = IpAddress::Ipv4(ipv4.dst_addr());
                self.dispatch(src, dst, ipv4.next_header(), ipv4.payload(), now);
            }
            IpVersion::Ipv6 => {
                let Ok(ipv6) = Ipv6Packet::new_checked(packet) else {
                    self.stats.malformed += 1;
                    return;
                };
                let src = IpAddress::Ipv6(ipv6.src_addr());
                let dst = IpAddress::Ipv6(ipv6.dst_addr());
                self.dispatch(src, dst, ipv6.next_header(), ipv6.payload(), now);
            }
        }

        self.device.push_rx(packet.to_vec());
        self.poll(now);
    }

    /// Poll the interface, then collect the socket side effects: received bytes, closed flows,
    /// received datagrams.
    pub fn poll(&mut self, now: Instant) {
        self.iface.poll(now, &mut self.device, &mut self.sockets);
        self.collect();
    }

    /// Everything the stack wants written to the TUN fd.
    pub fn egress(&mut self) -> Vec<Vec<u8>> {
        let packets = self.device.drain_tx();
        for packet in &packets {
            self.stats.packets_out += 1;
            self.stats.bytes_out += packet.len() as u64;
        }
        packets
    }

    /// The next deadline the stack needs a `poll` for (TCP retransmission, keepalive, delayed ACK,
    /// FIN timers). The engine turns this into one shared timer instead of polling at a fixed rate.
    pub fn poll_at(&mut self, now: Instant) -> Option<Instant> {
        self.iface.poll_at(now, &self.sockets)
    }

    pub fn tcp_flows(&self) -> impl Iterator<Item = &TcpFlow> {
        self.tcp.values()
    }

    pub fn tcp_flow(&self, key: &TcpKey) -> Option<&TcpFlow> {
        self.tcp.get(key)
    }

    pub fn tcp_flow_count(&self) -> usize {
        self.tcp.len()
    }

    pub fn udp_binding_count(&self) -> usize {
        self.udp.len()
    }

    /// Drain up to `out.len()` received bytes of one flow (the client-to-outbound direction).
    pub fn tcp_read(&mut self, key: &TcpKey, out: &mut [u8]) -> usize {
        let Some(flow) = self.tcp.get_mut(key) else {
            return 0;
        };
        let count = out.len().min(flow.recv.len());
        for (index, byte) in flow.recv.drain(..count).enumerate() {
            out[index] = byte;
        }
        count
    }

    /// Queue bytes towards the client (the outbound-to-client direction). Returns how many were
    /// accepted: a short write means the smoltcp send buffer is full and the caller must poll again
    /// before retrying, exactly like the Go engine's `Write` on the stack connection.
    pub fn tcp_write(&mut self, key: &TcpKey, data: &[u8], now: Instant) -> usize {
        let Some(flow) = self.tcp.get_mut(key) else {
            return 0;
        };
        if flow.closed {
            return 0;
        }
        let socket = self.sockets.get_mut::<tcp::Socket>(flow.handle);
        let written = socket.send_slice(data).unwrap_or(0);
        flow.tx_bytes += written as u64;
        flow.last_active = now;
        self.poll(now);
        written
    }

    /// Tear one connection down from the relay side.
    pub fn tcp_close(&mut self, key: &TcpKey, now: Instant) {
        let Some(flow) = self.tcp.get_mut(key) else {
            return;
        };
        if !flow.closed {
            let socket = self.sockets.get_mut::<tcp::Socket>(flow.handle);
            socket.close();
        }
        self.poll(now);
    }

    /// Forget a flow once the relay is done with it, releasing its socket and buffers.
    pub fn tcp_remove(&mut self, key: &TcpKey) {
        if let Some(flow) = self.tcp.remove(key) {
            if !flow.closed {
                self.sockets.remove(flow.handle);
            }
        }
    }

    /// The next datagram the engine has to answer, if any.
    pub fn udp_take(&mut self) -> Option<UdpDatagram> {
        self.datagrams.pop_front()
    }

    /// Send one datagram back to the client, addressed from the original destination it was sent
    /// to. This is what keeps `resolver_plain.go`'s "answer from the queried upstream" shape.
    pub fn udp_send(
        &mut self,
        local: IpEndpoint,
        peer: IpEndpoint,
        payload: &[u8],
        now: Instant,
    ) -> Result<(), UdpSendError> {
        let Some(binding) = self.udp.get(&local.port) else {
            return Err(UdpSendError::NotBound);
        };
        let handle = binding.handle;
        let socket = self.sockets.get_mut::<udp::Socket>(handle);
        let metadata = udp::UdpMetadata {
            endpoint: peer,
            local_address: Some(local.addr),
            meta: Default::default(),
        };
        socket
            .send_slice(payload, metadata)
            .map_err(|_| UdpSendError::Full)?;
        if let Some(binding) = self.udp.get_mut(&local.port) {
            binding.tx_bytes += payload.len() as u64;
        }
        self.stats.udp_datagrams_out += 1;
        self.poll(now);
        Ok(())
    }

    /// Drop flows whose client went away without a FIN (radio loss, app killed, Doze).
    pub fn expire_idle(&mut self, now: Instant) {
        let idle = self.limits.tcp_idle;
        let expired: Vec<TcpKey> = self
            .tcp
            .iter()
            .filter(|(_, flow)| !flow.closed && now - flow.last_active >= idle)
            .map(|(key, _)| *key)
            .collect();
        for key in expired {
            self.stats.tcp_expired += 1;
            self.tcp_remove(&key);
        }
    }

    fn dispatch(
        &mut self,
        src: IpAddress,
        dst: IpAddress,
        protocol: IpProtocol,
        payload: &[u8],
        now: Instant,
    ) {
        match protocol {
            IpProtocol::Tcp => {
                let Ok(packet) = TcpPacket::new_checked(payload) else {
                    self.stats.malformed += 1;
                    return;
                };
                let Ok(repr) = TcpRepr::parse(
                    &packet,
                    &src,
                    &dst,
                    &smoltcp::phy::ChecksumCapabilities::default(),
                ) else {
                    self.stats.malformed += 1;
                    return;
                };

                let local = IpEndpoint::new(dst, repr.dst_port);
                let remote = IpEndpoint::new(src, repr.src_port);
                let key = TcpKey::new(local, remote);

                match self.tcp.get_mut(&key) {
                    Some(flow) => flow.last_active = now,
                    None => {
                        if repr.control == TcpControl::Syn && repr.ack_number.is_none() {
                            self.open_tcp(key, now);
                        }
                    }
                }
            }
            IpProtocol::Udp => {
                let Ok(packet) = UdpPacket::new_checked(payload) else {
                    self.stats.malformed += 1;
                    return;
                };
                let Ok(repr) = UdpRepr::parse(
                    &packet,
                    &src,
                    &dst,
                    &smoltcp::phy::ChecksumCapabilities::default(),
                ) else {
                    self.stats.malformed += 1;
                    return;
                };
                if repr.dst_port == 0 {
                    self.stats.malformed += 1;
                    return;
                }
                self.ensure_udp(repr.dst_port);
            }
            _ => {}
        }
    }

    /// The SYN preprocessing step: one socket per flow, listening on the destination the client
    /// actually asked for.
    fn open_tcp(&mut self, key: TcpKey, now: Instant) {
        if self.tcp.len() >= self.limits.max_tcp_flows {
            self.stats.tcp_rejected += 1;
            return;
        }

        let mut socket = tcp::Socket::new(
            tcp::SocketBuffer::new(vec![0u8; self.limits.tcp_rx_bytes]),
            tcp::SocketBuffer::new(vec![0u8; self.limits.tcp_tx_bytes]),
        );
        socket.set_keep_alive(self.limits.keepalive);
        socket.set_timeout(Some(self.limits.tcp_idle));
        if socket.listen(key.local).is_err() {
            self.stats.tcp_rejected += 1;
            return;
        }

        let handle = self.sockets.add(socket);
        self.tcp.insert(key, TcpFlow::new(key, handle, now));
        self.stats.tcp_accepted += 1;
    }

    fn ensure_udp(&mut self, port: u16) {
        if self.udp.contains_key(&port) {
            return;
        }
        if self.udp.len() >= self.limits.max_udp_bindings {
            self.stats.udp_rejected += 1;
            return;
        }

        let mut socket = udp::Socket::new(
            udp::PacketBuffer::new(
                vec![udp::PacketMetadata::EMPTY; self.limits.udp_slots],
                vec![0u8; self.limits.udp_rx_bytes],
            ),
            udp::PacketBuffer::new(
                vec![udp::PacketMetadata::EMPTY; self.limits.udp_slots],
                vec![0u8; self.limits.udp_tx_bytes],
            ),
        );
        let endpoint = IpListenEndpoint { addr: None, port };
        if socket.bind(endpoint).is_err() {
            self.stats.udp_rejected += 1;
            return;
        }

        let handle = self.sockets.add(socket);
        self.udp.insert(
            port,
            UdpBinding {
                handle,
                port,
                rx_bytes: 0,
                tx_bytes: 0,
            },
        );
        self.stats.udp_bound += 1;
    }

    fn collect(&mut self) {
        let sockets = &mut self.sockets;
        let tcp = &mut self.tcp;
        let datagrams = &mut self.datagrams;
        let udp = &mut self.udp;
        let limits = self.limits;
        let mut stats = self.stats;

        for flow in tcp.values_mut() {
            if flow.closed {
                continue;
            }
            let socket = sockets.get_mut::<tcp::Socket>(flow.handle);
            flow.state = socket.state();
            flow.may_recv = socket.may_recv();
            flow.may_send = socket.may_send();

            while socket.can_recv() {
                let mut chunk = vec![0u8; 4096.min(limits.tcp_rx_bytes)];
                match socket.recv_slice(&mut chunk) {
                    Ok(read) => {
                        flow.recv.extend(chunk[..read].iter().copied());
                        flow.rx_bytes += read as u64;
                    }
                    Err(_) => break,
                }
            }

            if flow.recv.len() > limits.flow_buffer_bytes {
                // Nothing is draining this flow: drop it instead of buffering without bound.
                socket.abort();
                flow.recv.clear();
                flow.closed = true;
                stats.tcp_aborted_overflow += 1;
                sockets.remove(flow.handle);
                continue;
            }

            if socket.state() == tcp::State::Closed {
                flow.closed = true;
                stats.tcp_closed += 1;
                sockets.remove(flow.handle);
            }
        }

        for binding in udp.values_mut() {
            let socket = sockets.get_mut::<udp::Socket>(binding.handle);
            while let Ok((payload, metadata)) = socket.recv() {
                let Some(local_address) = metadata.local_address else {
                    continue;
                };
                datagrams.push_back(UdpDatagram {
                    local: IpEndpoint::new(local_address, binding.port),
                    peer: metadata.endpoint,
                    payload: payload.to_vec(),
                });
                binding.rx_bytes += payload.len() as u64;
                stats.udp_datagrams_in += 1;
            }
        }

        self.stats = stats;
    }
}

/// Why a datagram could not be queued for the client.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UdpSendError {
    /// No datagram was ever received on that port, so no socket is bound to it.
    NotBound,
    /// The socket's transmit buffer is full; the caller must retry after a poll.
    Full,
}

impl core::fmt::Display for UdpSendError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            Self::NotBound => f.write_str("udp port not bound"),
            Self::Full => f.write_str("udp send buffer full"),
        }
    }
}

impl Netstack {
    /// Whether the interface is in transparent mode. The spike's whole claim rests on this flag, so
    /// a future refactor that drops it fails loudly here.
    pub fn any_ip(&self) -> bool {
        self.iface.any_ip()
    }

    /// Switch transparent mode off. Only used by the spike's negative control: it must be left on
    /// in the engine, otherwise `smoltcp` drops every packet addressed to a foreign destination.
    pub fn set_any_ip(&mut self, any_ip: bool) {
        self.iface.set_any_ip(any_ip);
    }
}
