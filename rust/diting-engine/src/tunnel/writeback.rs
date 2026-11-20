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
            None => net.tcp_close_write(&key, crate::netstack::now()),
        }
    }

    pub fn flush_all(&mut self, net: &mut Netstack) {
        let keys: Vec<TcpKey> = self.entries.keys().copied().collect();
        for key in keys {
            if let Some(entry) = self.entries.get_mut(&key) {
                flush(&key, entry, net);
            }
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

fn flush(key: &TcpKey, entry: &mut Entry, net: &mut Netstack) {
    let mut now = crate::netstack::now();
    let before = entry.at;
    while entry.at < entry.data.len() {
        let written = net.tcp_write(key, &entry.data[entry.at..], now);
        if written == 0 {
            break;
        }
        entry.at += written;
        now = crate::netstack::now();
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
            net.tcp_close_write(key, now);
        }
    } else if entry.at >= 64 * 1024 {
        entry.data.drain(..entry.at);
        entry.at = 0;
    }
}
