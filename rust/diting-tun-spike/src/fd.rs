#[cfg(unix)]
pub use unix::TunFd;
#[cfg(unix)]
pub use unix::{dup_fd, FdSink, FdSource, OwnedFd};
#[cfg(not(unix))]
pub use unsupported::Unsupported;

pub const UNSUPPORTED: &str =
    "TUN file descriptors are only available on Android (unix); this host uses LoopbackSource";

#[cfg(unix)]
mod unix {
    use std::io;
    use std::os::unix::io::RawFd;

    use libc::{c_int, c_void, size_t};

    use super::super::io::{Fault, PacketSink, PacketSource};

    #[derive(Debug)]
    pub struct OwnedFd {
        raw: RawFd,
    }

    impl OwnedFd {
        pub fn as_raw_fd(&self) -> RawFd {
            self.raw
        }
    }

    impl Drop for OwnedFd {
        fn drop(&mut self) {
            unsafe {
                libc::close(self.raw);
            }
        }
    }

    pub fn dup_fd(raw: RawFd) -> Result<OwnedFd, String> {
        if raw < 0 {
            return Err(format!("invalid TUN file descriptor {raw}"));
        }
        let duped = unsafe { libc::dup(raw) };
        if duped < 0 {
            return Err(format!(
                "dup(TUN fd {raw}) failed: {}",
                io::Error::last_os_error()
            ));
        }
        let owned = OwnedFd { raw: duped };
        set_nonblocking(owned.raw)?;
        Ok(owned)
    }

    fn set_nonblocking(fd: RawFd) -> Result<(), String> {
        let flags = unsafe { libc::fcntl(fd, libc::F_GETFL) };
        if flags < 0 {
            return Err(format!(
                "fcntl(F_GETFL) failed: {}",
                io::Error::last_os_error()
            ));
        }
        if unsafe { libc::fcntl(fd, libc::F_SETFL, flags | libc::O_NONBLOCK) } < 0 {
            return Err(format!(
                "fcntl(F_SETFL, O_NONBLOCK) failed: {}",
                io::Error::last_os_error()
            ));
        }
        Ok(())
    }

    pub fn classify(errno: c_int) -> Fault {
        match errno {
            libc::EAGAIN | libc::EINTR => Fault::Again,
            libc::ENETDOWN | libc::EBUSY | libc::ENOBUFS | libc::EIO | libc::EMSGSIZE => {
                Fault::Backoff
            }
            _ => Fault::Fatal,
        }
    }

    pub struct FdSource {
        fd: OwnedFd,
    }

    impl FdSource {
        pub fn from_raw(raw: RawFd) -> Result<FdSource, String> {
            Ok(FdSource { fd: dup_fd(raw)? })
        }

        pub fn raw_fd(&self) -> RawFd {
            self.fd.as_raw_fd()
        }
    }

    impl PacketSource for FdSource {
        fn recv(&self, buf: &mut [u8]) -> Result<usize, Fault> {
            let read = unsafe {
                libc::read(
                    self.fd.as_raw_fd(),
                    buf.as_mut_ptr() as *mut c_void,
                    buf.len() as size_t,
                )
            };
            if read > 0 {
                return Ok(read as usize);
            }
            if read == 0 {
                return Err(Fault::Backoff);
            }
            Err(classify(
                io::Error::last_os_error().raw_os_error().unwrap_or(0),
            ))
        }

        fn wake(&self) {
        }
    }

    pub struct FdSink {
        fd: OwnedFd,
    }

    impl FdSink {
        pub fn from_raw(raw: RawFd) -> Result<FdSink, String> {
            Ok(FdSink { fd: dup_fd(raw)? })
        }
    }

    impl PacketSink for FdSink {
        fn send(&self, packet: &[u8]) -> Result<usize, Fault> {
            let written = unsafe {
                libc::write(
                    self.fd.as_raw_fd(),
                    packet.as_ptr() as *const c_void,
                    packet.len() as size_t,
                )
            };
            if written >= 0 {
                return Ok(written as usize);
            }
            Err(classify(
                io::Error::last_os_error().raw_os_error().unwrap_or(0),
            ))
        }
    }

    pub struct TunFd {
        pub reader: FdSource,
        pub writer: FdSink,
    }

    impl TunFd {
        pub fn from_raw(raw: RawFd) -> Result<TunFd, String> {
            Ok(TunFd {
                reader: FdSource::from_raw(raw)?,
                writer: FdSink::from_raw(raw)?,
            })
        }
    }

    #[cfg(test)]
    pub fn adopt_file(raw: RawFd) -> std::fs::File {
        unsafe { std::fs::File::from_raw_fd(raw) }
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use crate::io::Fault;
        use std::io::{Read, Write};
        use std::os::unix::io::{AsRawFd, FromRawFd};

        fn socket_pair() -> (std::fs::File, std::fs::File) {
            let mut fds = [0 as libc::c_int; 2];
            let rc =
                unsafe { libc::socketpair(libc::AF_UNIX, libc::SOCK_DGRAM, 0, fds.as_mut_ptr()) };
            assert_eq!(rc, 0, "socketpair: {}", std::io::Error::last_os_error());
            (adopt_file(fds[0]), adopt_file(fds[1]))
        }

        #[test]
        fn a_one_byte_fd_is_rejected_before_dup() {
            assert!(dup_fd(-1).is_err());
        }

        #[test]
        fn dup_hands_out_an_independent_descriptor() {
            let (peer, _keep) = socket_pair();
            let dupe = dup_fd(peer.as_raw_fd()).expect("dup");
            assert_ne!(dupe.as_raw_fd(), peer.as_raw_fd(), "a different fd number");
        }

        #[test]
        fn a_packet_round_trips_through_the_duplicated_descriptor() {
            let (peer, keep) = socket_pair();
            let source = FdSource::from_raw(peer.as_raw_fd()).expect("source");
            let sink = FdSink::from_raw(peer.as_raw_fd()).expect("sink");

            let mut writer = keep;
            writer.write_all(b"packet").expect("write the peer end");

            let mut buf = [0u8; 64];
            let mut read = 0;
            for _ in 0..100 {
                match source.recv(&mut buf) {
                    Ok(n) => {
                        read = n;
                        break;
                    }
                    Err(Fault::Again) => std::thread::sleep(std::time::Duration::from_millis(5)),
                    Err(other) => panic!("unexpected fault {other:?}"),
                }
            }
            assert_eq!(&buf[..read], b"packet");

            assert_eq!(sink.send(b"back").expect("send"), 4);
            let mut echoed = [0u8; 16];
            let n = writer.read(&mut echoed).expect("read the echo");
            assert_eq!(&echoed[..n], b"back");
        }

        #[test]
        fn an_empty_device_reports_again_instead_of_blocking() {
            let (peer, _keep) = socket_pair();
            let source = FdSource::from_raw(peer.as_raw_fd()).expect("source");
            let mut buf = [0u8; 16];
            assert_eq!(source.recv(&mut buf), Err(Fault::Again));
        }

        #[test]
        fn a_closed_descriptor_is_fatal() {
            let (peer, _keep) = socket_pair();
            let source = FdSource::from_raw(peer.as_raw_fd()).expect("source");
            let raw = source.raw_fd();
            unsafe {
                libc::close(raw);
            }
            let mut buf = [0u8; 16];
            assert_eq!(source.recv(&mut buf), Err(Fault::Fatal));
        }

        #[test]
        fn errno_classification_matches_the_documented_policy() {
            assert_eq!(classify(libc::EAGAIN), Fault::Again);
            assert_eq!(classify(libc::EINTR), Fault::Again);
            assert_eq!(classify(libc::ENETDOWN), Fault::Backoff);
            assert_eq!(classify(libc::EBUSY), Fault::Backoff);
            assert_eq!(classify(libc::ENOBUFS), Fault::Backoff);
            assert_eq!(classify(libc::EBADF), Fault::Fatal);
            assert_eq!(classify(libc::ENODEV), Fault::Fatal);
        }

        #[test]
        fn the_nonblocking_flag_is_set_on_the_duplicate() {
            let (peer, _keep) = socket_pair();
            let owned = dup_fd(peer.as_raw_fd()).expect("dup");
            let flags = unsafe { libc::fcntl(owned.as_raw_fd(), libc::F_GETFL) };
            assert_ne!(flags & libc::O_NONBLOCK, 0, "O_NONBLOCK must be set");
        }
    }
}

#[cfg(not(unix))]
mod unsupported {
    #[derive(Debug)]
    pub struct Unsupported;

    impl Unsupported {
        pub fn from_raw(_raw: i32) -> Result<Unsupported, String> {
            Err(super::UNSUPPORTED.to_string())
        }
    }
}
