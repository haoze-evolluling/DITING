//! The downstream half of the Go stack connection's backpressure.
//!
//! Go blocked the relay goroutine in `Write` until the client's receive window reopened. The Rust
//! relay reads upstream at its own pace and sends [`Event::Write`](super::queue::Event::Write)
//! commands, so bytes the smoltcp send buffer cannot take yet have to wait here instead of being
//! dropped (dropping them truncates a TLS/HTTP stream with no way for TCP to retransmit).
//!
//! # Backpressure, not a guillotine
//!
//! The first cut of this file only capped the backlog and aborted the flow past
//! [`MAX_PENDING_WRITE`](MAX_PENDING_WRITE). That silently broke every download larger than the cap:
//! the upstream copy task races ahead of the ~32 KiB socket send buffer, the backlog explodes past
//! the cap, and a perfectly healthy multi-megabyte response (a QQ/HTTP file download) is reset after
//! roughly one socket buffer. Go never did that because `Write` *blocked*.
//!
//! So the relay reserves payload bytes from a per-flow [`Semaphore`] before pushing a `Write` and
//! stops reading upstream while the reservation is unavailable; the stack releases the reservation
//! as it hands bytes to smoltcp. The per-flow backlog therefore stays under `MAX_PENDING_WRITE` while
//! the client drains, which is exactly the blocking behaviour the Go engine had. A `None` grant
//! (intercepted/DNS flows that do not reserve) keeps the old bounded-abort safety net.

use std::collections::HashMap;
use std::sync::Arc;

use tokio::sync::Semaphore;

use crate::netstack::{Netstack, TcpKey};

/// Bytes one flow may buffer while the client is not reading.
pub const MAX_PENDING_WRITE: usize = 1 << 20;

#[derive(Default)]
struct Entry {
    data: Vec<u8>,
    at: usize,
    close_after_pending: bool,
    /// The reservation to refund as bytes leave `data` for the socket. `None` for producers that
    /// never reserved (intercepted/DNS), which fall back to the bounded-abort safety net.
    credit: Option<Arc<Semaphore>>,
}

/// Every flow's unwritten bytes, drained as the smoltcp send window reopens.
#[derive(Default)]
pub struct WriteBacklog {
    entries: HashMap<TcpKey, Entry>,
}

impl WriteBacklog {
    /// Queues `data` and writes what the stack accepts now. `true` means the backlog exceeded the
    /// cap: the caller must abort the flow and call [`forget`](Self::forget). With a `credit` grant
    /// the relay already reserved these bytes, so this cap is only a safety net.
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

    /// Marks the handler's EOF; the FIN is sent only after the buffered bytes drain.
    pub fn close(&mut self, key: TcpKey, net: &mut Netstack) {
        match self.entries.get_mut(&key) {
            Some(entry) => {
                entry.close_after_pending = true;
                flush(&key, entry, net);
            }
            None => net.tcp_close_write(&key, crate::netstack::now()),
        }
    }

    /// Retries every flow after a poll: the ACKs just read may have reopened a send window.
    pub fn flush_all(&mut self, net: &mut Netstack) {
        let keys: Vec<TcpKey> = self.entries.keys().copied().collect();
        for key in keys {
            if let Some(entry) = self.entries.get_mut(&key) {
                flush(&key, entry, net);
            }
        }
    }

    /// Drops a flow's backlog when the flow itself goes away, closing its reservation so a relay
    /// blocked on the write budget wakes and ends.
    pub fn forget(&mut self, key: &TcpKey) {
        if let Some(entry) = self.entries.remove(key) {
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
            // These bytes are now smoltcp's to retransmit, so the relay may read more from upstream.
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
        // Reclaim the drained prefix so a long transfer does not keep the whole response.
        entry.data.drain(..entry.at);
        entry.at = 0;
    }
}
