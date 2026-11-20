use std::sync::{Arc, RwLock};

pub trait Protector: Send + Sync + 'static {
    fn protect(&self, fd: i64) -> bool;
}

#[derive(Clone, Default)]
pub struct ProtectorHandle {
    slot: Arc<RwLock<Option<Arc<dyn Protector>>>>,
}

impl ProtectorHandle {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn install(&self, protector: Arc<dyn Protector>) {
        *self.write() = Some(protector);
    }

    pub fn clear(&self) {
        *self.write() = None;
    }

    pub fn is_installed(&self) -> bool {
        self.read().is_some()
    }

    pub fn protect(&self, fd: i64) -> bool {
        let protector = self.read().clone();
        match protector {
            Some(protector) => protector.protect(fd),
            None => true,
        }
    }

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
