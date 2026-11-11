//! `VpnService.protect`: the one rule that keeps the tunnel from swallowing its own traffic.
//!
//! Every outbound socket the engine opens — plain DNS, DoT, DoH, DoQ, the bootstrap queries and the
//! later direct/proxy relays — must be protected **before** it connects. An unprotected socket to
//! an address that the VPN routes into the TUN comes back as a packet the engine reads again: a
//! routing loop that drains the battery and answers nothing.
//!
//! Go passed a `func(fd int) bool` down to each dial site and forgot it in a couple of places. Here
//! the protector is a per-engine handle that the dialer consults structurally
//! ([`crate::resolver::dial::Dialer`]), so a new socket path either goes through the dialer or does
//! not compile into the data plane at all.
//!
//! # Fail closed
//!
//! Kotlin's `protect()` returns `false` when the platform refuses (multi-user, some ROMs, a revoked
//! VPN). [`ProtectorHandle::protect_socket`] turns that into an error and **no `connect` happens**:
//! a flow that cannot be protected is dropped and logged instead of silently leaving the tunnel.
//!
//! # No protector means no VPN
//!
//! Server mode (the standalone DNS server) has no `VpnService` and Go passed a nil protector there.
//! [`ProtectorHandle`] with nothing installed answers `true`, which is that same no-op.

use std::sync::{Arc, RwLock};

/// The Kotlin callback: `boolean protect(long)` in gomobile's generated signatures, so the
/// descriptor travels as an `i64` (`int` on unix, `SOCKET` on the Windows host tests).
pub trait Protector: Send + Sync + 'static {
    /// `VpnService.protect(fd)`. `false` means the socket must not be used.
    fn protect(&self, fd: i64) -> bool;
}

/// The engine's protector slot, cloned into every dialer.
#[derive(Clone, Default)]
pub struct ProtectorHandle {
    slot: Arc<RwLock<Option<Arc<dyn Protector>>>>,
}

impl ProtectorHandle {
    pub fn new() -> Self {
        Self::default()
    }

    /// Installs (or replaces) the Kotlin protector.
    pub fn install(&self, protector: Arc<dyn Protector>) {
        *self.write() = Some(protector);
    }

    /// Drops the protector; the next dial stops protecting (only correct once the VPN is gone).
    pub fn clear(&self) {
        *self.write() = None;
    }

    pub fn is_installed(&self) -> bool {
        self.read().is_some()
    }

    /// The raw predicate. `true` when no protector is installed, which is the server-mode no-op.
    pub fn protect(&self, fd: i64) -> bool {
        let protector = self.read().clone();
        match protector {
            Some(protector) => protector.protect(fd),
            None => true,
        }
    }

    /// Protects an already-created, not-yet-connected socket.
    ///
    /// The error text is the one the engine logs; the caller must not connect afterwards.
    pub fn protect_socket(&self, fd: i64) -> Result<(), String> {
        if self.protect(fd) {
            Ok(())
        } else {
            Err(format!("protect refused fd {fd}"))
        }
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, Option<Arc<dyn Protector>>> {
        self.slot.read().unwrap_or_else(|error| error.into_inner())
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, Option<Arc<dyn Protector>>> {
        self.slot.write().unwrap_or_else(|error| error.into_inner())
    }
}

impl std::fmt::Debug for ProtectorHandle {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ProtectorHandle")
            .field("installed", &self.is_installed())
            .finish()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicI64, Ordering};

    struct Refusing;
    impl Protector for Refusing {
        fn protect(&self, _fd: i64) -> bool {
            false
        }
    }

    struct Recorder(AtomicI64);
    impl Protector for Recorder {
        fn protect(&self, fd: i64) -> bool {
            self.0.store(fd, Ordering::Relaxed);
            true
        }
    }

    #[test]
    fn without_a_protector_every_socket_is_allowed() {
        let handle = ProtectorHandle::new();
        assert!(!handle.is_installed());
        assert!(handle.protect(7));
        assert!(handle.protect_socket(7).is_ok());
    }

    #[test]
    fn a_refusal_is_an_error_the_dialer_cannot_ignore() {
        let handle = ProtectorHandle::new();
        handle.install(Arc::new(Refusing));
        assert_eq!(
            handle.protect_socket(11).unwrap_err(),
            "protect refused fd 11"
        );
    }

    #[test]
    fn the_installed_protector_sees_the_socket_descriptor() {
        let handle = ProtectorHandle::new();
        let recorder = Arc::new(Recorder(AtomicI64::new(0)));
        handle.install(recorder.clone());
        assert!(handle.protect(42));
        assert_eq!(recorder.0.load(Ordering::Relaxed), 42);
        handle.clear();
        assert!(!handle.is_installed());
    }

    #[test]
    fn replacing_the_protector_is_visible_to_every_clone() {
        let handle = ProtectorHandle::new();
        let clone = handle.clone();
        handle.install(Arc::new(Refusing));
        assert!(!clone.protect(3));
    }
}
