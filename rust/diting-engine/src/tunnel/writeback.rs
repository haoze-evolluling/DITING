use std::collections::HashMap;
use std::sync::Arc;

use tokio::sync::Semaphore;

use crate::netstack::{Netstack, TcpKey};

pub const MAX_PENDING_WRITE: usize = 1 << 20;

#[derive(Default)]
struct Entry {
    data: Vec<u8>,
    at: usize,
    close_after_pending: bool,
    credit: Option<Arc<Semaphore>>,
}

#[derive(Default)]
pub struct WriteBacklog {
    entries: HashMap<TcpKey, Entry>,
}

impl WriteBacklog {
    pub fn enqueue(
        &mut self,
        key: TcpKey,
        data: &[u8],
        credit: Option<Arc<Semaphore>>,
        net: &mut Netstack,
    ) -> bool {
        let entry = self.entries.entry(key).or_default();
        if entry.credit.is_none() {
            entry.credit = credit;
        }
        entry.data.extend_from_slice(data);
        flush(&key, entry, net);
        entry.data.len() - entry.at > MAX_PENDING_WRITE
    }

    pub fn close(&mut self, key: TcpKey, net: &mut Netstack) {
        match self.entries.get_mut(&key) {
            Some(entry) => {
                entry.close_after_pending = true;
                flush(&key, entry, net);
            }
            None => net.tcp_close_write_now(&key),
        }
    }

    pub fn flush_all(&mut self, net: &mut Netstack) {
        // `entries` 与 `net` 是两个不同的字段，`iter_mut` 可以直接借用，
        // 不必每轮循环先收集一份 key 列表。
        for (key, entry) in self.entries.iter_mut() {
            flush(key, entry, net);
        }
    }

    pub fn forget(&mut self, key: &TcpKey) {
        if let Some(entry) = self.entries.remove(key) {
            if let Some(credit) = entry.credit {
                credit.close();
            }
        }
    }
}

impl Drop for WriteBacklog {
    fn drop(&mut self) {
        for (_, entry) in self.entries.drain() {
            if let Some(credit) = entry.credit {
                credit.close();
            }
        }
    }
}

/// 把积压的数据塞进 smoltcp 的发送缓冲。**不** poll：发送由会话循环在一批写完之后统一做，
/// 否则一次 `flush` 里每写一块就要遍历一遍整个 socket 表。
fn flush(key: &TcpKey, entry: &mut Entry, net: &mut Netstack) {
    let before = entry.at;
    while entry.at < entry.data.len() {
        let now = crate::netstack::now();
        let written = net.tcp_write_now(key, &entry.data[entry.at..], now);
        if written > 0 {
            entry.at += written;
            continue;
        }
        // 发送缓冲满了：发一次包腾出窗口再重试。腾不出来说明对端窗口也满了，
        // 剩下的留到下一轮；此时 smoltcp 自己有定时器，循环不会被无限占用。
        if !net.poll_transmit(now) {
            break;
        }
    }
    let flushed = entry.at - before;
    if flushed > 0 {
        if let Some(credit) = &entry.credit {
            credit.add_permits(flushed);
        }
    }
    if entry.at == entry.data.len() {
        entry.data.clear();
        entry.at = 0;
        if entry.close_after_pending {
            entry.close_after_pending = false;
            net.tcp_close_write_now(key);
        }
    } else if entry.at >= 64 * 1024 {
        entry.data.drain(..entry.at);
        entry.at = 0;
    }
}
