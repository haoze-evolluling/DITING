//! Encrypted DNS listener lifecycle (DoT/DoH/DoQ) and the DDR answer it feeds.
//!
//! The listeners are an implementation detail of [`AppRuntime`], so this module lives beside the
//! runtime and keeps the state private to the `runtime` module tree. DDR is derived from what is
//! actually bound: advertising a port that failed to bind would point clients at a dead service.

use std::sync::{Arc, RwLock};

use diting_desktop_api::config::security::{
    CERT_SOURCE_SELF_SIGNED, DEFAULT_DOH_PORT, DEFAULT_DOQ_PORT, DEFAULT_DOT_PORT,
};
use diting_desktop_api::config::Config;
use diting_desktop_core::cert::{derive_cert_names, CertManager};
use diting_desktop_dns::encrypted::{
    EncryptedConfig, EncryptedListeners, ReverseProxyConfig as ListenerReverseProxyConfig,
};
use diting_desktop_dns::server::DnsServer;
use diting_desktop_dns::stages::ddr::{cert_has_ips, DdrAnswer, DdrProvider};

use super::AppRuntime;

/// Answers RFC 9462 probes from the endpoints that are bound right now.
///
/// The answer is recomputed per query (it is cheap) so that stopping or restarting a listener is
/// reflected immediately.
pub(super) struct EncryptedDdrProvider {
    config: Arc<RwLock<Config>>,
    listeners: Arc<RwLock<Option<Arc<EncryptedListeners>>>>,
    cert: Arc<CertManager>,
}

impl EncryptedDdrProvider {
    fn answer_for(
        config: &Config,
        listeners: Option<&EncryptedListeners>,
        cert_ips: &[String],
    ) -> DdrAnswer {
        let Some(listeners) = listeners else {
            return DdrAnswer::default();
        };
        if !listeners.enabled() {
            return DdrAnswer::default();
        }
        let encrypted = &config.encrypted;
        DdrAnswer {
            server_name: encrypted.server_name.clone(),
            dot_enabled: listeners.dot_address().is_some(),
            doh_enabled: listeners.doh_address().is_some(),
            doq_enabled: listeners.doq_address().is_some(),
            dot_port: bound_port(
                listeners.dot_address(),
                encrypted.dot_port,
                DEFAULT_DOT_PORT,
            ),
            doh_port: bound_port(
                listeners.doh_address(),
                encrypted.doh_port,
                DEFAULT_DOH_PORT,
            ),
            doq_port: bound_port(
                listeners.doq_address(),
                encrypted.doq_port,
                DEFAULT_DOQ_PORT,
            ),
            doh_path: encrypted.doh_path.clone(),
            cert_has_ips: cert_has_ips(cert_ips),
        }
    }
}

impl DdrProvider for EncryptedDdrProvider {
    fn answer(&self) -> DdrAnswer {
        let config = self
            .config
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        let listeners = self
            .listeners
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        let cert_ips = self.cert.info().ip_addresses;
        Self::answer_for(&config, listeners.as_deref(), &cert_ips)
    }
}

/// The port a listener actually bound to, falling back to the configured (validated) port.
fn bound_port(address: Option<&str>, configured: i32, default: i32) -> u16 {
    address
        .and_then(|address| address.rsplit_once(':'))
        .and_then(|(_, port)| port.parse::<u16>().ok())
        .or_else(|| u16::try_from(configured).ok())
        .unwrap_or(u16::try_from(default).unwrap_or(0))
}

/// Ports are validated by `EncryptedDNSConfig::normalize`; the fallback covers configs written by
/// hand or by an older version.
fn encrypted_port(configured: i32, default: i32) -> u16 {
    u16::try_from(configured).unwrap_or_else(|_| u16::try_from(default).unwrap_or(0))
}

impl AppRuntime {
    pub(super) fn ddr_provider(&self) -> Option<Arc<dyn DdrProvider>> {
        if !self.config().encrypted.enabled {
            return None;
        }
        Some(Arc::new(EncryptedDdrProvider {
            config: Arc::clone(&self.config),
            listeners: Arc::clone(&self.encrypted),
            cert: Arc::clone(&self.cert),
        }))
    }

    /// Restarts only the DoT/DoH/DoQ listeners, leaving the 53 socket untouched.
    ///
    /// Go's `reloadDNSWithCurrentConfig`: a certificate or port change must not blip plaintext
    /// resolution (clients would fall back to another resolver mid-flight).
    pub async fn reload_encrypted(&self) {
        self.stop_encrypted().await;
        let server = self.dns.lock().await.clone();
        let Some(server) = server else {
            return;
        };
        let config = self.config();
        self.set_encrypted(self.start_encrypted(&config, server).await);
    }

    /// The bound encrypted endpoints, as `(dot, doh, doq)`.
    pub fn encrypted_addresses(&self) -> (Option<String>, Option<String>, Option<String>) {
        let listeners = self
            .encrypted
            .read()
            .unwrap_or_else(|error| error.into_inner())
            .clone();
        match listeners {
            Some(listeners) => (
                listeners.dot_address().map(str::to_string),
                listeners.doh_address().map(str::to_string),
                listeners.doq_address().map(str::to_string),
            ),
            None => (None, None, None),
        }
    }

    pub(super) fn set_encrypted(&self, listeners: Option<EncryptedListeners>) {
        let previous = {
            let mut guard = self
                .encrypted
                .write()
                .unwrap_or_else(|error| error.into_inner());
            std::mem::replace(&mut *guard, listeners.map(Arc::new))
        };
        // The caller stops the previous instance before calling in, so this is only a safety net
        // against two concurrent restarts leaking accept loops.
        if let Some(previous) = previous {
            if previous.enabled() {
                eprintln!("[加密DNS] 旧的监听器未停止，已丢弃引用（重启竞态）");
            }
        }
    }

    pub(super) async fn stop_encrypted(&self) {
        let previous = {
            let mut guard = self
                .encrypted
                .write()
                .unwrap_or_else(|error| error.into_inner());
            guard.take()
        };
        if let Some(previous) = previous {
            previous.shutdown().await;
        }
    }

    /// Generates or renews the self-signed certificate before a listener is started.
    ///
    /// Imported certificates are left alone: replacing an operator's certificate with a
    /// self-signed one would hide the real configuration problem behind a certificate no client
    /// trusts.
    fn prepare_certificate(&self, config: &Config) {
        let cert_config = &config.encrypted.cert;
        if !cert_config.source.is_empty() && cert_config.source != CERT_SOURCE_SELF_SIGNED {
            self.cert.reload();
            return;
        }
        let mut cert = cert_config.clone();
        if cert.dns_names.is_empty() && cert.ip_addresses.is_empty() {
            let (dns_names, ip_addresses) = derive_cert_names(
                &config.encrypted.server_name,
                &config.encrypted.listen_address,
            );
            cert.dns_names = dns_names;
            cert.ip_addresses = ip_addresses;
        }
        let result = if self.cert.health().needs_renewal() {
            self.cert.regenerate_self_signed(cert)
        } else {
            self.cert.ensure_self_signed(cert).map(|_| ())
        };
        if let Err(error) = result {
            eprintln!("[加密DNS] 自签证书生成/续签失败: {error}");
        }
    }

    pub(super) async fn start_encrypted(
        &self,
        config: &Config,
        server: Arc<DnsServer>,
    ) -> Option<EncryptedListeners> {
        let encrypted = &config.encrypted;
        if !encrypted.enabled
            || (!encrypted.dot_enabled && !encrypted.doh_enabled && !encrypted.doq_enabled)
        {
            return None;
        }
        self.prepare_certificate(config);
        let listener_config = EncryptedConfig {
            listen_address: encrypted.listen_address.clone(),
            dot_enabled: encrypted.dot_enabled,
            doh_enabled: encrypted.doh_enabled,
            doq_enabled: encrypted.doq_enabled,
            dot_port: encrypted_port(encrypted.dot_port, DEFAULT_DOT_PORT),
            doh_port: encrypted_port(encrypted.doh_port, DEFAULT_DOH_PORT),
            doq_port: encrypted_port(encrypted.doq_port, DEFAULT_DOQ_PORT),
            doh_path: encrypted.doh_path.clone(),
            server_name: encrypted.server_name.clone(),
            reverse_proxy: ListenerReverseProxyConfig {
                enabled: encrypted.reverse_proxy.enabled,
                trusted_sources: encrypted.reverse_proxy.trusted_sources.clone(),
                client_ip_header: encrypted.reverse_proxy.client_ip_header.clone(),
            },
        };
        match EncryptedListeners::start(server, Arc::clone(&self.cert), listener_config).await {
            Ok(listeners) => {
                let addresses = listeners.addresses();
                println!("[加密DNS] 已启动加密监听器: {addresses:?}");
                Some(listeners)
            }
            Err(error) => {
                eprintln!("[加密DNS] 加密监听器启动失败: {error}");
                None
            }
        }
    }
}
