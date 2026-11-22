pub mod callback;
pub mod fd;
pub mod io;
pub mod jni_bridge;
pub mod pipeline;
pub mod protector;
pub mod stats;

#[cfg(unix)]
pub type RawSocket = std::os::unix::io::RawFd;
#[cfg(windows)]
pub type RawSocket = std::os::windows::io::RawSocket;
