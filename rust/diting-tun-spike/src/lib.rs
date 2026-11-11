//! Stage 0 Spike 3 for the Android engine migration: the JNI facade, TUN descriptor ownership,
//! `VpnService.protect` ordering and the callback thread model.
//!
//! Stage 3 (`TUN + netstack + 极速模式`) is the first stage that has to own an Android file
//! descriptor and call back into Kotlin from Rust-owned threads. Those four things are independent of
//! the netstack, and each one can fail in a way the host tests would never see:
//!
//! | question | where it is answered |
//! | --- | --- |
//! | Can the engine own the fd Kotlin detached? | [`fd`] — `dup`, `O_NONBLOCK`, errno → [`io::Fault`]; unix-only, compile-checked for Android |
//! | Is `protect` guaranteed to run before `connect`? | [`protector`] — the socket is created, protected, and only then connected; a refusal fails closed |
//! | Which thread calls Kotlin? | [`callback`] — one named thread owns the JVM attachment; producers only `try_send` |
//! | Can `stop`/`free` race a running pipeline? | [`pipeline`] + [`jni_bridge`] — handle registry with `Arc`s, an interruptible stop, joins in a fixed order |
//!
//! The prototype is device-independent on purpose: the JVM smoke test
//! (`rust/tools/tun-spike-smoke`) drives the real JNI symbols with a real JVM, a real `protect`
//! callback and a real loopback connection, while the packet source is
//! [`io::LoopbackSource`] instead of `/dev/tun`. What that leaves unverified is device-side only.

pub mod callback;
pub mod fd;
pub mod io;
pub mod jni_bridge;
pub mod pipeline;
pub mod protector;
pub mod stats;

/// The descriptor type `VpnService.protect` takes: an `int` on Android, a `SOCKET` on a Windows host.
#[cfg(unix)]
pub type RawSocket = std::os::unix::io::RawFd;
/// Windows hosts hand a `SOCKET` to `protect`; the Kotlin side takes both as a `long`.
#[cfg(windows)]
pub type RawSocket = std::os::windows::io::RawSocket;
