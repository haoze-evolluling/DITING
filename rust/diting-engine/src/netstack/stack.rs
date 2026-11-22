mod tcp;
mod udp;

use std::collections::{BTreeMap, VecDeque};

use smoltcp::iface::{Config as IfaceConfig, Interface, SocketSet};
use smoltcp::time::{Duration, Instant};
use smoltcp::wire::{
    HardwareAddress, IpAddress, IpCidr, IpEndpoint, IpProtocol, IpVersion, Ipv4Packet, Ipv6Packet,
    TcpControl, TcpPacket, TcpRepr, UdpPacket, UdpRepr,
};

use crate::netstack::device::IpDevice;
use crate::netstack::flow::{Stats, TcpFlow, TcpKey, UdpBinding, UdpDatagram};

pub use udp::UdpSendError;

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
            // 收窗口翻倍以提升高 RTT 下的上行吞吐；同时把并发上限减半，
            // 最坏内存占用仍与原先持平。
            max_tcp_flows: 2048,
            max_udp_bindings: 2048,
            tcp_rx_bytes: 64 * 1024,
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
    pub(super) sockets: SocketSet<'static>,
    pub(super) limits: Limits,
    pub(super) tcp: BTreeMap<TcpKey, TcpFlow>,
    pub(super) udp: BTreeMap<u16, UdpBinding>,
    pub(super) datagrams: VecDeque<UdpDatagram>,
    pub(super) opened: VecDeque<TcpKey>,
    pub(super) expire_scratch: Vec<TcpKey>,
    pub(super) next_expire: Option<Instant>,
    pub(super) stats: Stats,
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
            opened: VecDeque::new(),
            expire_scratch: Vec::new(),
            next_expire: None,
            stats: Stats::default(),
        }
    }

    pub fn limits(&self) -> Limits {
        self.limits
    }

    pub fn mtu(&self) -> usize {
        self.limits.mtu
    }

    pub fn stats(&self) -> Stats {
        self.stats
    }

    pub fn any_ip(&self) -> bool {
        self.iface.any_ip()
    }

    /// 收一个入站包。
    ///
    /// 取所有权而不是 `&[u8]`：调用方（收包线程）手里本来就是这个 `Vec`，借用再复制一遍
    /// 纯属为了绕开借用检查器。解析借用在上面的 `match` 结束时就释放，之后可以安全 move。
    ///
    /// 这里**不** poll：`Interface::poll` 会遍历整个 SocketSet（上限 4096），把它放在每个包上
    /// 等于每包一次全表扫描。调用方在消化完一批事件后统一 poll 一次即可。
    pub fn ingress(&mut self, packet: Vec<u8>, now: Instant) {
        self.stats.packets_in += 1;
        self.stats.bytes_in += packet.len() as u64;

        let malformed = match IpVersion::of_packet(&packet) {
            Ok(IpVersion::Ipv4) => match Ipv4Packet::new_checked(&packet) {
                Ok(ipv4) => {
                    let src = IpAddress::Ipv4(ipv4.src_addr());
                    let dst = IpAddress::Ipv4(ipv4.dst_addr());
                    self.dispatch(src, dst, ipv4.next_header(), ipv4.payload(), now);
                    false
                }
                Err(_) => true,
            },
            Ok(IpVersion::Ipv6) => match Ipv6Packet::new_checked(&packet) {
                Ok(ipv6) => {
                    let src = IpAddress::Ipv6(ipv6.src_addr());
                    let dst = IpAddress::Ipv6(ipv6.dst_addr());
                    self.dispatch(src, dst, ipv6.next_header(), ipv6.payload(), now);
                    false
                }
                Err(_) => true,
            },
            Err(_) => true,
        };

        if malformed {
            self.stats.malformed += 1;
            return;
        }

        self.device.push_rx(packet);
    }

    pub fn poll(&mut self, now: Instant) {
        self.iface.poll(now, &mut self.device, &mut self.sockets);
        self.collect();
    }

    /// poll 一次并报告是否真的发出了包。
    ///
    /// 写回队列一次可能积压几百 KB，而单个 socket 的发送缓冲只有 32 KB；
    /// 写不进去时用它发一次包腾出窗口再重试，否则积压会一直留在队列里，
    /// 而 `poll_delay` 看不到队列，循环就会白白空等一个超时周期。
    pub fn poll_transmit(&mut self, now: Instant) -> bool {
        let before = self.device.pending_tx();
        self.iface.poll(now, &mut self.device, &mut self.sockets);
        self.collect();
        self.device.pending_tx() > before
    }

    /// 逐个取走出站包，避免每轮收集一次 `Vec`。
    pub fn take_egress(&mut self) -> Option<Vec<u8>> {
        let packet = self.device.tx_pop()?;
        self.stats.packets_out += 1;
        self.stats.bytes_out += packet.len() as u64;
        Some(packet)
    }

    pub fn poll_delay(&mut self, now: Instant) -> Option<Duration> {
        self.iface.poll_delay(now, &self.sockets)
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

    fn collect(&mut self) {
        self.collect_tcp();
        self.collect_udp();
    }
}
