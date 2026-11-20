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

#[derive(Clone, Copy, Debug)]
pub struct Limits {
    pub mtu: usize,
    pub max_tcp_flows: usize,
    pub max_udp_bindings: usize,
    pub tcp_rx_bytes: usize,
    pub tcp_tx_bytes: usize,
    pub udp_rx_bytes: usize,
    pub udp_tx_bytes: usize,
    pub flow_buffer_bytes: usize,
    pub udp_slots: usize,
    pub tcp_idle: Duration,
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

    pub fn poll(&mut self, now: Instant) {
        self.iface.poll(now, &mut self.device, &mut self.sockets);
        self.collect();
    }

    pub fn egress(&mut self) -> Vec<Vec<u8>> {
        let packets = self.device.drain_tx();
        for packet in &packets {
            self.stats.packets_out += 1;
            self.stats.bytes_out += packet.len() as u64;
        }
        packets
    }

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

    pub fn tcp_remove(&mut self, key: &TcpKey) {
        if let Some(flow) = self.tcp.remove(key) {
            if !flow.closed {
                self.sockets.remove(flow.handle);
            }
        }
    }

    pub fn udp_take(&mut self) -> Option<UdpDatagram> {
        self.datagrams.pop_front()
    }

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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum UdpSendError {
    NotBound,
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
    pub fn any_ip(&self) -> bool {
        self.iface.any_ip()
    }

    pub fn set_any_ip(&mut self, any_ip: bool) {
        self.iface.set_any_ip(any_ip);
    }
}
