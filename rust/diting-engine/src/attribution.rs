//! Flow attribution: 5-tuple → UID → package, with the kernels' TTL caches in front.
//!
//! `socket_uid_resolver.go` + `uid_cache.go` in Rust. The decision half (TTLs, the 1024/256 entry
//! caps, the negative-cache window and the prune-vs-reset behaviour) already lives in
//! [`diting_telemetry_core`]; this module keeps the two Kotlin callbacks and the lookup order:
//!
//! ```text
//! profile cache (2 s hit / 500 ms miss) → UIDResolver.resolveUID(...) → cache
//! package cache (60 s)                 → AppUidResolver.packageForUid(...) → cache
//! ```
//!
//! The direction is the one `UidPackageCache.kt` documents: **local = the app**, remote = the
//! destination the app dialed. Android's `getConnectionOwnerUid` wants exactly that pair, and Go hit
//! the same trap ("direction inversion") when it first wired tun2socks' endpoints backwards.
//!
//! # Blocking
//!
//! A miss is a binder round trip. The resolver runs on the stack thread (a plain Rust thread, not a
//! tokio worker), which is where Go's flow goroutines ran theirs too. The caches keep the common
//! case — every packet of an established flow — to a mutex lookup.

use std::sync::{Arc, RwLock};

use diting_telemetry_core::uidcache::Addr;
use diting_telemetry_core::{FlowKey, FlowUidCache, UidPackageCache};
use smoltcp::wire::IpEndpoint;

/// `ProtocolTCP`.
pub const PROTOCOL_TCP: i32 = 6;
/// `ProtocolUDP`.
pub const PROTOCOL_UDP: i32 = 17;
/// `UIDUnknown`: an unattributable flow never matches an explicit rule.
pub const UID_UNKNOWN: i32 = -1;

/// `UIDResolver.resolveUID(protocol, localIP, localPort, remoteIP, remotePort)`.
pub trait UidResolver: Send + Sync + 'static {
    /// The UID that owns the app endpoint, or a non-positive value when it cannot be resolved.
    fn resolve(
        &self,
        protocol: i32,
        app_ip: &str,
        app_port: u16,
        server_ip: &str,
        server_port: u16,
    ) -> i32;
}

/// `AppUidResolver.packageForUid(uid)`; an empty string means "unknown".
pub trait AppUidResolver: Send + Sync + 'static {
    fn package_for(&self, uid: i32) -> String;
}

/// One engine's attribution state.
pub struct Attribution {
    flows: FlowUidCache,
    packages: UidPackageCache,
    uid_resolver: RwLock<Option<Arc<dyn UidResolver>>>,
    app_resolver: RwLock<Option<Arc<dyn AppUidResolver>>>,
}

impl Default for Attribution {
    fn default() -> Self {
        Self::new()
    }
}

impl Attribution {
    pub fn new() -> Self {
        Self {
            flows: FlowUidCache::new(),
            packages: UidPackageCache::new(),
            uid_resolver: RwLock::new(None),
            app_resolver: RwLock::new(None),
        }
    }

    pub fn install_uid_resolver(&self, resolver: Arc<dyn UidResolver>) {
        *self.uid_slot() = Some(resolver);
    }

    pub fn install_app_resolver(&self, resolver: Arc<dyn AppUidResolver>) {
        *self.app_slot() = Some(resolver);
    }

    /// Drops both callbacks (the caches are bounded and expire on their own; Go cleared the
    /// Kotlin-side cache, which lives in `UidPackageCache.kt` and is called from there).
    pub fn clear(&self) {
        *self.uid_slot() = None;
        *self.app_slot() = None;
    }

    pub fn clear_uid_resolver(&self) {
        *self.uid_slot() = None;
    }

    pub fn clear_app_resolver(&self) {
        *self.app_slot() = None;
    }

    /// The UID owning `app`, resolving and caching it on a miss.
    pub fn uid_for(&self, protocol: i32, app: IpEndpoint, server: IpEndpoint, now_ns: i64) -> i32 {
        let (Some(app_addr), Some(server_addr)) = (
            Addr::from_bytes(&crate::netstack::address_bytes(app.addr)),
            Addr::from_bytes(&crate::netstack::address_bytes(server.addr)),
        ) else {
            return UID_UNKNOWN;
        };
        let key = FlowKey::new(
            app_addr,
            i32::from(app.port),
            server_addr,
            i32::from(server.port),
            protocol,
        );
        if let Some(uid) = self.flows.lookup(&key, now_ns) {
            return uid;
        }
        let Some(resolver) = self.uid_slot().clone() else {
            return UID_UNKNOWN;
        };
        let uid = resolver.resolve(
            protocol,
            &address_text(app),
            app.port,
            &address_text(server),
            server.port,
        );
        self.flows.store(key, uid, now_ns);
        uid
    }

    /// The package name behind `uid`, or an empty string when it is unknown.
    pub fn package_for(&self, uid: i32, now_ns: i64) -> String {
        if uid == UID_UNKNOWN {
            return String::new();
        }
        if let Some(name) = self.packages.lookup(uid, now_ns) {
            return name;
        }
        let Some(resolver) = self.app_slot().clone() else {
            return String::new();
        };
        let name = resolver.package_for(uid);
        self.packages.store(uid, &name, now_ns);
        name
    }

    /// The name the connection log shows: the package, `uid:N`, or `unknown`.
    pub fn display_name(&self, uid: i32, now_ns: i64) -> String {
        let package = self.package_for(uid, now_ns);
        if !package.is_empty() {
            return package;
        }
        if uid != UID_UNKNOWN {
            return format!("uid:{uid}");
        }
        "unknown".to_string()
    }

    fn uid_slot(&self) -> std::sync::RwLockWriteGuard<'_, Option<Arc<dyn UidResolver>>> {
        self.uid_resolver
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }

    fn app_slot(&self) -> std::sync::RwLockWriteGuard<'_, Option<Arc<dyn AppUidResolver>>> {
        self.app_resolver
            .write()
            .unwrap_or_else(|error| error.into_inner())
    }
}

/// `net.IP.String()` for the two families the stack sees.
fn address_text(endpoint: IpEndpoint) -> String {
    crate::netstack::address_text(endpoint.addr)
}

/// The monotonic clock the caches want (they never read one themselves).
pub fn now_ns() -> i64 {
    crate::resolver::now_ns()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicUsize, Ordering};

    struct Fixed(i32, AtomicUsize);
    impl UidResolver for Fixed {
        fn resolve(
            &self,
            _protocol: i32,
            _app: &str,
            _app_port: u16,
            _server: &str,
            _port: u16,
        ) -> i32 {
            self.1.fetch_add(1, Ordering::Relaxed);
            self.0
        }
    }

    struct Names;
    impl AppUidResolver for Names {
        fn package_for(&self, uid: i32) -> String {
            format!("app{uid}")
        }
    }

    fn endpoints() -> (IpEndpoint, IpEndpoint) {
        (
            "10.0.0.2:1234".parse().expect("app"),
            "1.1.1.1:53".parse().expect("server"),
        )
    }

    #[test]
    fn a_first_lookup_hits_jni_and_the_second_does_not() {
        let attribution = Attribution::new();
        let counter = Arc::new(Fixed(10123, AtomicUsize::new(0)));
        attribution.install_uid_resolver(counter.clone());
        attribution.install_app_resolver(Arc::new(Names));
        let (app, server) = endpoints();
        assert_eq!(attribution.uid_for(PROTOCOL_UDP, app, server, 0), 10123);
        assert_eq!(attribution.uid_for(PROTOCOL_UDP, app, server, 1), 10123);
        assert_eq!(counter.1.load(Ordering::Relaxed), 1);
        assert_eq!(attribution.package_for(10123, 2), "app10123");
        assert_eq!(attribution.display_name(10123, 3), "app10123");
        assert_eq!(attribution.display_name(-1, 4), "unknown");
    }

    #[test]
    fn a_negative_uid_is_cached_briefly_and_never_named() {
        let attribution = Attribution::new();
        let counter = Arc::new(Fixed(-1, AtomicUsize::new(0)));
        attribution.install_uid_resolver(counter.clone());
        let (app, server) = endpoints();
        assert_eq!(attribution.uid_for(PROTOCOL_TCP, app, server, 0), -1);
        // The negative window is 500 ms.
        assert_eq!(
            attribution.uid_for(PROTOCOL_TCP, app, server, 600_000_000),
            -1
        );
        assert_eq!(counter.1.load(Ordering::Relaxed), 2);
        assert_eq!(attribution.display_name(-1, 0), "unknown");
    }

    #[test]
    fn without_a_resolver_everything_stays_unknown() {
        let attribution = Attribution::new();
        let (app, server) = endpoints();
        assert_eq!(attribution.uid_for(PROTOCOL_TCP, app, server, 0), -1);
        assert_eq!(attribution.display_name(4242, 0), "uid:4242");
    }

    #[test]
    fn the_ipv6_text_is_the_go_spelling() {
        let endpoint: IpEndpoint = "[2001:db8::1]:853".parse().expect("v6");
        assert_eq!(address_text(endpoint), "2001:db8::1");
    }
}
