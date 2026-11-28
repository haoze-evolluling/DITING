use smoltcp::socket::tcp;
use smoltcp::time::{Duration, Instant};

use crate::netstack::flow::{FlowOutput, TcpFlow, TcpKey};

use super::Netstack;

/// `expire_idle` 的最小间隔。
const EXPIRE_INTERVAL: Duration = Duration::from_secs(1);
/// 从 smoltcp 环形缓冲搬入 `TcpFlow` 时每次取的最大字节数。
const RECV_CHUNK: usize = 4096;

impl Netstack {
    pub fn take_opened(&mut self) -> Option<TcpKey> {
        self.opened.pop_front()
    }

    pub fn tcp_flow(&self, key: &TcpKey) -> Option<&TcpFlow> {
        self.tcp.get(key)
    }

    pub fn tcp_flow_count(&self) -> usize {
        self.tcp.len()
    }

    pub fn take_tcp_output(&mut self) -> Vec<FlowOutput> {
        let mut output = Vec::new();
        for flow in self.tcp.values_mut() {
            let data = flow.take_data();
            let eof = flow.recv_closed && !flow.eof_reported;
            if eof {
                flow.eof_reported = true;
            }
            if data.is_empty() && !eof && !flow.closed {
                continue;
            }
            output.push(FlowOutput {
                key: flow.key,
                data,
                eof,
                closed: flow.closed,
            });
        }
        output
    }

    /// 把数据放进某个流的发送缓冲；**不** poll，调用方在批量写完后统一 poll。
    /// 写回队列一次 `flush` 可能连写几十块，逐块 poll 等于逐块全表扫描。
    pub fn tcp_write_now(&mut self, key: &TcpKey, data: &[u8], now: Instant) -> usize {
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
        written
    }

    pub fn tcp_close_write_now(&mut self, key: &TcpKey) {
        if let Some(flow) = self.tcp.get_mut(key) {
            if !flow.closed {
                self.sockets.get_mut::<tcp::Socket>(flow.handle).close();
            }
        }
    }

    pub fn tcp_abort_now(&mut self, key: &TcpKey) {
        if let Some(flow) = self.tcp.get_mut(key) {
            if !flow.closed {
                self.sockets.get_mut::<tcp::Socket>(flow.handle).abort();
            }
        }
    }

    pub fn tcp_remove(&mut self, key: &TcpKey) {
        if let Some(flow) = self.tcp.remove(key) {
            if !flow.closed {
                self.sockets.remove(flow.handle);
            }
        }
    }

    /// 中止所有 TCP 流（网络切换时旧链路上的连接已必然失效）。
    ///
    /// 这里只调用 `abort()` 而**不**立即 `remove`：下一次 `poll` 会走 smoltcp 的
    /// CLOSED 分支给客户端发 RST，随后 `collect_tcp` 再摘掉 socket。
    pub fn abort_all_tcp(&mut self) {
        let sockets = &mut self.sockets;
        for flow in self.tcp.values_mut() {
            if !flow.closed {
                sockets.get_mut::<tcp::Socket>(flow.handle).abort();
            }
        }
    }

    /// Relay 流的上行信用窗口；由会话线程在流打开时挂上。
    pub(crate) fn set_upload_gate(
        &mut self,
        key: &TcpKey,
        gate: std::sync::Arc<tokio::sync::Semaphore>,
    ) {
        if let Some(flow) = self.tcp.get_mut(key) {
            flow.upload = Some(gate);
        }
    }

    /// 内部通道一时腾不出位置时，把已取出的数据按原顺序放回队首，
    /// 等下一次 poll 再投递；eof 标记同样延后。
    pub fn tcp_requeue(&mut self, key: &TcpKey, data: Vec<u8>, eof: bool) {
        let Some(flow) = self.tcp.get_mut(key) else {
            return;
        };
        flow.push_chunk_front(data);
        if eof {
            flow.eof_reported = false;
        }
    }

    /// 空闲流回收。`tcp_idle` 是 300 秒，而这里原来每轮事件批次都要全表扫一遍
    /// （上限 2048）并分配一个 `Vec`；改成每秒最多一次，且复用 scratch。
    pub fn expire_idle(&mut self, now: Instant) {
        if self.next_expire.is_some_and(|next| now < next) {
            return;
        }
        self.next_expire = Some(now + EXPIRE_INTERVAL);

        let idle = self.limits.tcp_idle;
        let mut expired = std::mem::take(&mut self.expire_scratch);
        expired.clear();
        for (key, flow) in &self.tcp {
            if !flow.closed && now - flow.last_active >= idle {
                expired.push(*key);
            }
        }
        for key in &expired {
            self.stats.tcp_expired += 1;
            self.tcp_remove(key);
        }
        self.expire_scratch = expired;
    }

    pub(super) fn open_tcp(&mut self, key: TcpKey, now: Instant) {
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
        self.opened.push_back(key);
        self.stats.tcp_accepted += 1;
    }

    pub(super) fn collect_tcp(&mut self) {
        let sockets = &mut self.sockets;
        let tcp = &mut self.tcp;
        let limits = self.limits;
        let stats = &mut self.stats;
        // 搬运用中转缓冲：所有流复用同一块栈缓冲，不再每个 4KiB 造一个 `Vec`。
        let mut scratch = [0u8; RECV_CHUNK];

        for flow in tcp.values_mut() {
            if flow.closed {
                continue;
            }
            let socket = sockets.get_mut::<tcp::Socket>(flow.handle);
            flow.state = socket.state();
            flow.may_recv = socket.may_recv();
            flow.may_send = socket.may_send();
            flow.recv_closed = matches!(
                flow.state,
                tcp::State::CloseWait
                    | tcp::State::Closing
                    | tcp::State::LastAck
                    | tcp::State::TimeWait
                    | tcp::State::Closed
            );

            // 只有拿到上行信用才继续从 smoltcp 搬数据；信用耗尽时收包缓冲
            // 会自然填满并关小 TCP 窗口，把压力交还给发送端。
            let mut budget = flow
                .upload
                .as_ref()
                .map_or(usize::MAX, |gate| gate.available_permits());
            let room = limits.flow_buffer_bytes.saturating_sub(flow.buffered());
            let mut drained = 0usize;
            while socket.can_recv() && budget > 0 && drained < room {
                let want = RECV_CHUNK.min(budget).min(room - drained);
                match socket.recv_slice(&mut scratch[..want]) {
                    Ok(0) => break,
                    Ok(read) => {
                        // 一块数据只付一次分配，块的所有权之后直接交给流任务。
                        flow.push_chunk(scratch[..read].to_vec());
                        flow.rx_bytes += read as u64;
                        drained += read;
                        budget -= read;
                    }
                    Err(_) => break,
                }
            }
            if drained > 0 {
                if let Some(gate) = &flow.upload {
                    if let Ok(permit) = gate.clone().try_acquire_many_owned(drained as u32) {
                        permit.forget();
                    }
                }
            }

            // 没有信用窗口的流（拦截/DNS）保留溢出保护。
            if flow.upload.is_none() && flow.buffered() > limits.flow_buffer_bytes {
                socket.abort();
                flow.clear_recv();
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
    }
}
