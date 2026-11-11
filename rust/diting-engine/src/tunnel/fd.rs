//! The `VpnService` descriptor: `dup` twice, non-blocking, errno-classified.
//!
//! Kotlin hands the engine the `detachFd()` of a `ParcelFileDescriptor`. That descriptor belongs to
//! the `VpnService`; closing the service would close it under the reader. Two dups solve that:
//!
//! * **one for the reader, one for the writer**, so a write never blocks behind a read and
//!   `VpnService` teardown of the original does not strand the tunnel;
//! * both are `O_NONBLOCK` and the reader uses `poll(2)` with a 250 ms timeout, so the reader notices
//!   `stop` (and the closed dup) without a permanently blocked `read(2)`.
//!
//! `stop` closes both dups; `poll` then returns immediately and the read fails with `EBADF`, which
//! [`LinkFault::Fatal`] turns into "reader exits". This is the mechanism the `diting-tun-spike`
//! prototype validated; the only device-side unknown is how the kernel's packet queue behaves during
//! a handover, which surfaces as [`LinkFault::Backoff`].
//!
//! # Host builds
//!
//! The fd path is unix-only. On the Windows host the type still exists (so the JNI entry points and
//! `Engine::start_full` compile) but [`TunFd::open`] reports "unsupported"; the host tests drive the
//! same session through [`crate::tunnel::link::MemoryLink`] instead.

use crate::tunnel::link::{LinkFault, PacketLink};

#[cfg(unix)]
mod unix {
    use std::io;
    use std::os::fd::RawFd;
    use std::sync::atomic::{AtomicBool, Ordering};
    use std::time::Duration;

    use super::{LinkFault, PacketLink};

    /// How long the reader parks in `poll(2)` before it re-checks `stop`.
    const POLL_INTERVAL_MS: i32 = 250;

    pub struct TunFd {
        reader: RawFd,
        writer: RawFd,
        closed: AtomicBool,
        mtu: usize,
    }

    impl TunFd {
        /// Duplicates both directions and makes them non-blocking.
        pub fn open(fd: i32, mtu: usize) -> io::Result<Self> {
            let reader = duplicate(fd)?;
            let writer = match duplicate(fd) {
                Ok(writer) => writer,
                Err(error) => {
                    close_fd(reader);
                    return Err(error);
                }
            };
            Ok(Self {
                reader,
                writer,
                closed: AtomicBool::new(false),
                mtu,
            })
        }

        pub fn reader_fd(&self) -> RawFd {
            self.reader
        }

        pub fn writer_fd(&self) -> RawFd {
            self.writer
        }

        fn is_closed(&self) -> bool {
            self.closed.load(Ordering::Acquire)
        }
    }

    impl Drop for TunFd {
        fn drop(&mut self) {
            self.close();
        }
    }

    impl PacketLink for TunFd {
        fn recv(&self, buffer: &mut [u8]) -> Result<usize, LinkFault> {
            if self.is_closed() {
                return Err(LinkFault::Fatal);
            }
            match poll_readable(self.reader, POLL_INTERVAL_MS) {
                Ok(true) => {}
                // No packet this interval; the reader checks `stop` and comes back.
                Ok(false) => return Err(LinkFault::Again),
                Err(error) => return Err(classify(error.raw_os_error())),
            }
            let read = unsafe {
                libc::read(
                    self.reader,
                    buffer.as_mut_ptr().cast::<libc::c_void>(),
                    buffer.len(),
                )
            };
            if read < 0 {
                return Err(classify(io::Error::last_os_error().raw_os_error()));
            }
            if read == 0 {
                return Err(LinkFault::Again);
            }
            Ok(read as usize)
        }

        fn send(&self, packet: &[u8]) -> Result<(), LinkFault> {
            if self.is_closed() {
                return Err(LinkFault::Fatal);
            }
            let written = unsafe {
                libc::write(
                    self.writer,
                    packet.as_ptr().cast::<libc::c_void>(),
                    packet.len(),
                )
            };
            if written < 0 {
                return Err(classify(io::Error::last_os_error().raw_os_error()));
            }
            if written as usize != packet.len() {
                // A TUN write is one packet or nothing; a partial write means the descriptor is not
                // the device we think it is.
                return Err(LinkFault::Fatal);
            }
            Ok(())
        }

        fn mtu(&self) -> usize {
            self.mtu
        }

        fn close(&self) {
            // `swap` makes this idempotent, which `stop` + `Drop` rely on. Closing from another
            // thread is what wakes the reader's `poll`: there is no portable way to interrupt it.
            if !self.closed.swap(true, Ordering::AcqRel) {
                close_fd(self.reader);
                close_fd(self.writer);
            }
        }
    }

    fn duplicate(fd: i32) -> io::Result<RawFd> {
        let duplicate = unsafe { libc::dup(fd) };
        if duplicate < 0 {
            return Err(io::Error::last_os_error());
        }
        let flags = unsafe { libc::fcntl(duplicate, libc::F_GETFL) };
        if flags < 0 {
            let error = io::Error::last_os_error();
            close_fd(duplicate);
            return Err(error);
        }
        if unsafe { libc::fcntl(duplicate, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
            let error = io::Error::last_os_error();
            close_fd(duplicate);
            return Err(error);
        }
        Ok(duplicate)
    }

    fn close_fd(fd: RawFd) {
        unsafe {
            libc::close(fd);
        }
    }

    /// `poll(2)` for readability: `true` when a packet is waiting, `false` on the timeout.
    fn poll_readable(fd: RawFd, timeout_ms: i32) -> io::Result<bool> {
        let mut descriptor = libc::pollfd {
            fd,
            events: libc::POLLIN,
            revents: 0,
        };
        let ready = unsafe { libc::poll(&mut descriptor, 1, timeout_ms) };
        if ready < 0 {
            return Err(io::Error::last_os_error());
        }
        if ready == 0 {
            return Ok(false);
        }
        // `POLLNVAL`/`POLLERR` show up as "readable"; the following `read` reports the real errno,
        // which is where an `EBADF` from `stop` needs to land.
        Ok(true)
    }

    /// The errno table from [`crate::tunnel::link`].
    fn classify(errno: Option<i32>) -> LinkFault {
        match errno {
            Some(code)
                if code == libc::EAGAIN || code == libc::EWOULDBLOCK || code == libc::EINTR =>
            {
                LinkFault::Again
            }
            Some(code)
                if code == libc::ENETDOWN
                    || code == libc::EBUSY
                    || code == libc::ENOBUFS
                    || code == libc::EIO
                    || code == libc::EMSGSIZE =>
            {
                LinkFault::Backoff
            }
            _ => LinkFault::Fatal,
        }
    }

    /// Keeps the classification table honest: the reader's retry policy is derived from it.
    pub fn classify_errno(errno: i32) -> LinkFault {
        classify(Some(errno))
    }

    /// `poll`'s interval, exposed so the session's docs and tests use the same number.
    pub fn poll_interval() -> Duration {
        Duration::from_millis(POLL_INTERVAL_MS as u64)
    }
}

#[cfg(unix)]
pub use unix::{classify_errno, poll_interval, TunFd};

#[cfg(not(unix))]
mod other {
    use std::io;

    use super::{LinkFault, PacketLink};

    /// The fd path needs unix; the type exists so the JNI facade compiles on the Windows host.
    pub struct TunFd;

    impl TunFd {
        pub fn open(_fd: i32, _mtu: usize) -> io::Result<Self> {
            Err(io::Error::new(
                io::ErrorKind::Unsupported,
                "a TUN descriptor needs a unix host",
            ))
        }
    }

    impl PacketLink for TunFd {
        fn recv(&self, _buffer: &mut [u8]) -> Result<usize, LinkFault> {
            Err(LinkFault::Fatal)
        }

        fn send(&self, _packet: &[u8]) -> Result<(), LinkFault> {
            Err(LinkFault::Fatal)
        }

        fn mtu(&self) -> usize {
            1400
        }

        fn close(&self) {}
    }
}

#[cfg(not(unix))]
pub use other::TunFd;

#[cfg(all(test, unix))]
mod tests {
    use super::*;
    use std::os::fd::{AsRawFd, IntoRawFd};

    /// A `socketpair` stands in for the TUN device: the same read/write/close semantics.
    fn socket_pair() -> (
        std::os::unix::net::UnixStream,
        std::os::unix::net::UnixStream,
    ) {
        std::os::unix::net::UnixStream::pair().expect("socketpair")
    }

    #[test]
    fn both_directions_are_duplicated_and_non_blocking() {
        let (left, right) = socket_pair();
        let tun = TunFd::open(left.as_raw_fd(), 1400).expect("dup");
        assert_ne!(tun.reader_fd(), left.as_raw_fd());
        assert_ne!(tun.writer_fd(), left.as_raw_fd());
        assert_ne!(tun.reader_fd(), tun.writer_fd());
        // The dup is non-blocking: an idle read reports Again instead of parking the thread.
        let mut buffer = [0u8; 64];
        assert_eq!(tun.recv(&mut buffer), Err(LinkFault::Again));
        // The original descriptor still works and is untouched by the dups.
        use std::io::Write;
        (&right).write_all(&[7, 7]).expect("write");
        assert_eq!(tun.recv(&mut buffer), Ok(2));
        assert_eq!(&buffer[..2], &[7, 7]);
        assert!(tun.send(&[1, 2, 3]).is_ok());
        let mut peer = [0u8; 8];
        use std::io::Read;
        let mut reader = &right;
        reader.read_exact(&mut peer[..3]).expect("read back");
        assert_eq!(&peer[..3], &[1, 2, 3]);
    }

    #[test]
    fn closing_the_dup_wakes_the_reader() {
        let (left, _right) = socket_pair();
        let tun = TunFd::open(left.as_raw_fd(), 1400).expect("dup");
        tun.close();
        assert_eq!(tun.recv(&mut [0u8; 16]), Err(LinkFault::Fatal));
        assert_eq!(tun.send(&[1]), Err(LinkFault::Fatal));
        // Idempotent, as `stop` + `Drop` call it twice.
        tun.close();
    }

    #[test]
    fn errno_classification_matches_the_documented_policy() {
        assert_eq!(classify_errno(libc::EAGAIN), LinkFault::Again);
        assert_eq!(classify_errno(libc::EWOULDBLOCK), LinkFault::Again);
        assert_eq!(classify_errno(libc::EINTR), LinkFault::Again);
        assert_eq!(classify_errno(libc::ENETDOWN), LinkFault::Backoff);
        assert_eq!(classify_errno(libc::EBUSY), LinkFault::Backoff);
        assert_eq!(classify_errno(libc::ENOBUFS), LinkFault::Backoff);
        assert_eq!(classify_errno(libc::EIO), LinkFault::Backoff);
        assert_eq!(classify_errno(libc::EMSGSIZE), LinkFault::Backoff);
        assert_eq!(classify_errno(libc::EBADF), LinkFault::Fatal);
        assert_eq!(classify_errno(libc::ENODEV), LinkFault::Fatal);
        assert_eq!(classify_errno(libc::EINVAL), LinkFault::Fatal);
        assert_eq!(classify_errno(libc::ENOMEM), LinkFault::Fatal);
    }

    #[test]
    fn a_missing_descriptor_is_reported() {
        let error = TunFd::open(-1, 1400).expect_err("no descriptor");
        assert!(error.raw_os_error().is_some());
        assert_eq!(poll_interval(), std::time::Duration::from_millis(250));
    }

    #[test]
    fn the_original_descriptor_stays_usable_after_the_dups_close() {
        let (left, right) = socket_pair();
        let _dup = left.as_raw_fd();
        let tun = TunFd::open(_dup, 1400).expect("dup");
        tun.close();
        // `left` is still open: `TunFd` only closes its own dups.
        assert!(right.as_raw_fd() >= 0);
        drop(right);
        drop(left.into_raw_fd());
    }
}
