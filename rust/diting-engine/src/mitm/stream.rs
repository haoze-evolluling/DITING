//! The client side of an intercepted flow as a byte stream: the TUN channel seen as a socket.
//!
//! Go's MITM handlers worked on a `net.Conn`: `peekFlow` read the first bytes, then the same
//! connection was wrapped in `peekReplayConn` and handed to `tls.Server` or `http.ReadRequest`. Here
//! the flow arrives as a channel of [`Inbound`] frames and leaves as [`Event::Write`] commands, so
//! [`ClientStream`] is the adapter that makes the two look like one `AsyncRead + AsyncWrite`:
//!
//! ```text
//! poll_read  ← Inbound::Data / Inbound::Eof   (the session already counted these bytes as `tx`)
//! poll_write → Event::Write(key, …)           (and `rx` is counted here, like countingConn)
//! shutdown   → Event::CloseWrite              (the client FIN, i.e. TCP half-close)
//! ```
//!
//! # Peek
//!
//! [`ClientStream::peek`] is `peekFlow`: it waits up to ten seconds for the first bytes and hands them
//! back without consuming them, so the classification sees them and the TLS/HTTP parser sees them
//! again. Go did exactly one `Read`; this accumulates whatever has already arrived (still at most
//! [`PEEK_SIZE`]) because a ClientHello split across two segments is common on a mobile link and the
//! SNI parser needs the whole record to find the hostname.
//!
//! # Backpressure
//!
//! `Event::Write` is a queue push, so a client that stops reading makes the egress queue drop instead
//! of growing: the same "drop and let TCP retransmit" behaviour stage 3 chose for the whole data
//! plane.

use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::mpsc;

use crate::engine::Engine;
use crate::netstack::TcpKey;
use crate::tunnel::dnsflow::Inbound;
use crate::tunnel::queue::{Event, Events};

/// `peekSize`: how much of the first client burst the classifier may see.
pub const PEEK_SIZE: usize = 4 * 1024;
/// `peekTimeout`.
pub const PEEK_TIMEOUT: Duration = Duration::from_secs(10);

/// One intercepted TCP flow's client side.
pub struct ClientStream {
    key: TcpKey,
    events: Arc<Events>,
    rx: mpsc::Receiver<Inbound>,
    engine: Arc<Engine>,
    uid: i32,
    /// The bytes `peek` handed back; served before anything new is read.
    peeked: Vec<u8>,
    peeked_at: usize,
    /// The tail of a frame the caller's buffer had no room for.
    pending: Vec<u8>,
    pending_at: usize,
    eof: bool,
    closed_write: bool,
}

impl ClientStream {
    pub fn new(
        engine: Arc<Engine>,
        events: Arc<Events>,
        key: TcpKey,
        uid: i32,
        rx: mpsc::Receiver<Inbound>,
    ) -> ClientStream {
        ClientStream {
            key,
            events,
            rx,
            engine,
            uid,
            peeked: Vec::new(),
            peeked_at: 0,
            pending: Vec::new(),
            pending_at: 0,
            eof: false,
            closed_write: false,
        }
    }

    /// `peekFlow`: the first bytes of the flow, or empty when the client said nothing.
    ///
    /// The bytes stay queued: a later `poll_read` serves them again before touching the channel.
    pub async fn peek(&mut self, timeout: Duration) -> Vec<u8> {
        if !self.peeked.is_empty() || self.eof {
            return self.peeked.clone();
        }
        let first = match tokio::time::timeout(timeout, self.rx.recv()).await {
            Ok(Some(Inbound::Data(data))) => data,
            // A timeout, a closed channel and a client that left immediately all classify as
            // "nothing to peek at": the handler gives up on the flow, like `len(peeked) == 0` did.
            Ok(Some(Inbound::Eof)) | Ok(None) | Err(_) => {
                self.eof = true;
                return Vec::new();
            }
        };
        self.take_peeked(first);
        // Take whatever else is already queued so a split ClientHello still parses.
        while self.peeked.len() < PEEK_SIZE {
            match self.rx.try_recv() {
                Ok(Inbound::Data(data)) => self.take_peeked(data),
                Ok(Inbound::Eof) => {
                    self.eof = true;
                    break;
                }
                Err(_) => break,
            }
        }
        self.peeked.clone()
    }

    /// Adds one frame to the peek buffer and parks whatever does not fit for `poll_read`.
    fn take_peeked(&mut self, data: Vec<u8>) {
        let room = PEEK_SIZE.saturating_sub(self.peeked.len());
        let take = data.len().min(room);
        self.peeked.extend_from_slice(&data[..take]);
        if take < data.len() {
            let mut rest = data[take..].to_vec();
            rest.extend_from_slice(&self.pending[self.pending_at..]);
            self.pending = rest;
            self.pending_at = 0;
        }
    }

    /// The bytes `peek` returned, without consuming them again.
    pub fn peeked(&self) -> &[u8] {
        &self.peeked
    }

    /// `defer conn.Close()`: tell the client there is nothing more coming.
    pub fn close_write(&mut self) {
        if self.closed_write {
            return;
        }
        self.closed_write = true;
        self.events.push_command(Event::CloseWrite(self.key));
    }

    /// A reset: the flow is gone and the stack should drop the socket without a FIN exchange.
    pub fn abort(&self) {
        self.events.push_command(Event::Abort(self.key));
    }

    fn take(&mut self, buf: &mut ReadBuf<'_>, from: Source) -> bool {
        let (data, at) = match from {
            Source::Peek => (&self.peeked, &mut self.peeked_at),
            Source::Pending => (&self.pending, &mut self.pending_at),
        };
        let rest = &data[*at..];
        if rest.is_empty() {
            return false;
        }
        let take = rest.len().min(buf.remaining());
        buf.put_slice(&rest[..take]);
        *at += take;
        true
    }

    fn refill(&mut self, cx: &mut Context<'_>) -> Poll<()> {
        loop {
            match self.rx.poll_recv(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(Some(Inbound::Data(data))) => {
                    self.pending = data;
                    self.pending_at = 0;
                    if self.pending.is_empty() {
                        continue;
                    }
                    return Poll::Ready(());
                }
                Poll::Ready(Some(Inbound::Eof)) | Poll::Ready(None) => {
                    self.eof = true;
                    return Poll::Ready(());
                }
            }
        }
    }
}

#[derive(Clone, Copy)]
enum Source {
    Peek,
    Pending,
}

impl AsyncRead for ClientStream {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        let this = self.get_mut();
        loop {
            if this.take(buf, Source::Peek) || this.take(buf, Source::Pending) {
                return Poll::Ready(Ok(()));
            }
            if this.eof {
                return Poll::Ready(Ok(()));
            }
            match this.refill(cx) {
                Poll::Pending => return Poll::Pending,
                Poll::Ready(()) => continue,
            }
        }
    }
}

impl AsyncWrite for ClientStream {
    fn poll_write(
        self: Pin<&mut Self>,
        _cx: &mut Context<'_>,
        data: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        let this = self.get_mut();
        if data.is_empty() {
            return Poll::Ready(Ok(0));
        }
        // Bytes on their way to the client: `countingConn`'s `rx` direction.
        this.engine.traffic().record(this.uid, 0, data.len() as i64);
        this.events
            .push_command(Event::Write(this.key, data.to_vec(), None));
        Poll::Ready(Ok(data.len()))
    }

    fn poll_flush(self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Poll::Ready(Ok(()))
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, _cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        self.close_write();
        Poll::Ready(Ok(()))
    }
}
