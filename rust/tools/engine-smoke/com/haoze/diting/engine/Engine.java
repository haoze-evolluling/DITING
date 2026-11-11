package com.haoze.diting.engine;

/// The engine class the app will use, declared here exactly as the Kotlin facade will be.
///
/// The smoke test loads the host `libditing_engine` and drives this class, so a renamed native, a
/// swapped argument order or a wrong callback signature fails on the host instead of on a phone.
/// Method names are the gomobile-generated ones the current Kotlin call sites already use
/// (`applyDNSConfig`, `applyRuleSnapshot`, `startStandalone`, …), so moving a call site to the new
/// facade is a change of import, not of spelling.
public final class Engine {
    private long handle;

    public Engine() {
        handle = nativeNew();
        check(handle != 0, "engine handle");
    }

    /// The engine handed to the JVM by `nativeNew`; the Kotlin facade keeps it private too.
    public long handle() {
        return handle;
    }

    public void free() {
        if (handle != 0) {
            nativeFree(handle);
            handle = 0;
        }
    }

    public void stop() {
        requireHandle();
        nativeStop(handle);
    }

    public void stopStandalone() {
        requireHandle();
        nativeStopStandalone(handle);
    }

    /// Null on success, otherwise the error text (Go returned an `error` here).
    public String startStandalone(long port) {
        requireHandle();
        return nativeStartStandalone(handle, port);
    }

    /// The port the server is listening on; 0 when it is not running.
    public long standalonePort() {
        requireHandle();
        return nativeStandalonePort(handle);
    }

    public boolean isRunning() {
        requireHandle();
        return nativeIsRunning(handle);
    }

    /// Null on success, otherwise the error text.
    public String applyDNSConfig(String json) {
        requireHandle();
        return nativeApplyDnsConfig(handle, json);
    }

    /// Empty on success, otherwise the rejection text.
    public String applyRuleSnapshot(String json) {
        requireHandle();
        return nativeApplyRuleSnapshot(handle, json);
    }

    public void setRewriteRules(String json) {
        requireHandle();
        nativeSetRewriteRules(handle, json);
    }

    public void setFilterDNS(boolean enabled) {
        requireHandle();
        nativeSetFilterDns(handle, enabled);
    }

    public void setBlockResponseType(String responseType) {
        requireHandle();
        nativeSetBlockResponseType(handle, responseType);
    }

    public void clearDNSCache() {
        requireHandle();
        nativeClearDnsCache(handle);
    }

    public String getStats() {
        requireHandle();
        return nativeGetStats(handle);
    }

    public String getDNSCacheStats() {
        requireHandle();
        return nativeGetDnsCacheStats(handle);
    }

    public String getDNSCacheEntries(long limit) {
        requireHandle();
        return nativeGetDnsCacheEntries(handle, limit);
    }

    public String resolveDomain(String domain, boolean ipv4) {
        requireHandle();
        return nativeResolveDomain(handle, domain, ipv4);
    }

    public void setBatchLogCallback(BatchLogCallback callback) {
        requireHandle();
        nativeSetBatchLogCallback(handle, callback);
    }

    public void setRaceLogCallback(RaceLogCallback callback) {
        requireHandle();
        nativeSetRaceLogCallback(handle, callback);
    }

    public void setBootstrapLogCallback(BootstrapLogCallback callback) {
        requireHandle();
        nativeSetBootstrapLogCallback(handle, callback);
    }

    // ---- outbound proxy (stage 4a) --------------------------------------------------------

    public String configureOutboundProxy(String configJson) {
        requireHandle();
        String error = nativeConfigureOutboundProxy(handle, configJson);
        return error == null ? "" : error;
    }

    public void setOutboundProxyStatusCallback(OutboundProxyStatusCallback callback) {
        requireHandle();
        nativeSetOutboundProxyStatusCallback(handle, callback);
    }

    // ---- TUN data plane (stage 3) ---------------------------------------------------------

    public void startFull(long fd, SocketProtector protector) {
        requireHandle();
        if (protector != null) {
            nativeSetSocketProtector(handle, protector);
        }
        String error = nativeStartFull(handle, fd);
        if (error != null) {
            throw new IllegalStateException(error);
        }
    }

    public void stopFull() {
        requireHandle();
        nativeStopFull(handle);
    }

    public void releaseTun() {
        requireHandle();
        nativeReleaseTun(handle);
    }

    public boolean isFullRunning() {
        requireHandle();
        return nativeIsFullRunning(handle);
    }

    public void setSocketProtector(SocketProtector callback) {
        requireHandle();
        nativeSetSocketProtector(handle, callback);
    }

    public void setUIDResolver(UIDResolver callback) {
        requireHandle();
        nativeSetUidResolver(handle, callback);
    }

    public void setAppUidResolver(AppUidResolver callback) {
        requireHandle();
        nativeSetAppUidResolver(handle, callback);
    }

    public void setTrafficCallback(TrafficCallback callback) {
        requireHandle();
        nativeSetTrafficCallback(handle, callback);
    }

    public void setBlockedUIDs(String uidsCsv) {
        requireHandle();
        nativeSetBlockedUids(handle, uidsCsv);
    }

    public void setFilterHttp3(boolean enabled) {
        requireHandle();
        nativeSetFilterHttp3(handle, enabled);
    }

    public void setBlockEncryptedDns(boolean enabled) {
        requireHandle();
        nativeSetBlockEncryptedDns(handle, enabled);
    }

    public void setTickIntervalMs(long millis) {
        requireHandle();
        nativeSetTickIntervalMs(handle, millis);
    }

    // ---- MITM (stage 4b) -----------------------------------------------------------------

    /// The root CA in PEM form, or "" when MITM could not start.
    public String startStackMitm(String certDir) {
        requireHandle();
        return nativeStartStackMitm(handle, certDir);
    }

    public void stopStackMitm() {
        requireHandle();
        nativeStopStackMitm(handle);
    }

    public boolean isMitmActive() {
        requireHandle();
        return nativeIsMitmActive(handle);
    }

    public String getMitmCACert(String certDir) {
        requireHandle();
        return nativeGetMitmCaCert(handle, certDir);
    }

    public void setMitmAllowedUIDs(String uidsCsv) {
        requireHandle();
        nativeSetMitmAllowedUids(handle, uidsCsv);
    }

    public void setHttpsBypassRules(String content) {
        requireHandle();
        nativeSetHttpsBypassRules(handle, content);
    }

    public void setExtraPassthroughSuffixes(String content) {
        requireHandle();
        nativeSetExtraPassthroughSuffixes(handle, content);
    }

    public void clearMitmBlacklist() {
        requireHandle();
        nativeClearMitmBlacklist(handle);
    }

    public long getMitmBlacklistCount() {
        requireHandle();
        return nativeMitmBlacklistCount(handle);
    }

    public void setCosmeticRules(String json) {
        requireHandle();
        nativeSetCosmeticRules(handle, json);
    }

    public void setRequestRules(String json) {
        requireHandle();
        nativeSetRequestRules(handle, json);
    }

    public void setHttpLogCallback(HttpLogCallback callback) {
        requireHandle();
        nativeSetHttpLogCallback(handle, callback);
    }

    private void requireHandle() {
        if (handle == 0) {
            throw new IllegalStateException("engine released");
        }
    }

    private static void check(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }

    /// `tunnel.BatchLogCallback.onDNSQueryBatch`.
    public interface BatchLogCallback {
        void onDNSQueryBatch(String jsonLogs);
    }

    /// `tunnel.RaceLogCallback.onRaceResult`: thirteen arguments, in this order.
    public interface RaceLogCallback {
        void onRaceResult(
                String queryName,
                long queryType,
                String strategy,
                long providerCount,
                boolean success,
                long elapsedMs,
                String selectedProviderID,
                long selectedElapsedMs,
                String winnerProviderID,
                long winnerElapsedMs,
                boolean fallbackUsed,
                boolean fallbackSuccess,
                String errorMessage);
    }

    /// `tunnel.BootstrapLogCallback.onBootstrapResult`.
    public interface BootstrapLogCallback {
        void onBootstrapResult(
                String ipID,
                String ipName,
                String ip,
                String host,
                boolean success,
                long elapsedMs,
                boolean fallbackUsed,
                String errorMessage);
    }

    /// `OutboundProxyStatusCallback.onOutboundProxyStatus(String, String)`.
    public interface OutboundProxyStatusCallback {
        void onOutboundProxyStatus(String state, String message);
    }

    /// `SocketProtector.protect(long): boolean`.
    public interface SocketProtector {
        boolean protect(long fd);
    }

    /// `UIDResolver.resolveUID(long, String, long, String, long): long`.
    public interface UIDResolver {
        long resolveUID(long protocol, String localIP, long localPort, String remoteIP,
                long remotePort);
    }

    /// `AppUidResolver.packageForUid(long): String`.
    public interface AppUidResolver {
        String packageForUid(long uid);
    }

    /// `TrafficCallback.onTrafficStatsTick(String)`.
    public interface TrafficCallback {
        void onTrafficStatsTick(String jsonDeltas);
    }

    /// `HttpLogCallback.onHttpEvent(String, String, String, String, String)`.
    public interface HttpLogCallback {
        void onHttpEvent(String packageName, String authority, String protocol, String outcome,
                String matchedRule);
    }

    private native long nativeNew();

    private native void nativeFree(long handle);

    private native void nativeStop(long handle);

    private native void nativeStopStandalone(long handle);

    private native String nativeStartStandalone(long handle, long port);

    private native long nativeStandalonePort(long handle);

    private native boolean nativeIsRunning(long handle);

    private native String nativeApplyDnsConfig(long handle, String json);

    private native String nativeApplyRuleSnapshot(long handle, String json);

    private native void nativeSetRewriteRules(long handle, String json);

    private native void nativeSetFilterDns(long handle, boolean enabled);

    private native void nativeSetBlockResponseType(long handle, String responseType);

    private native void nativeClearDnsCache(long handle);

    private native String nativeGetStats(long handle);

    private native String nativeGetDnsCacheStats(long handle);

    private native String nativeGetDnsCacheEntries(long handle, long limit);

    private native String nativeResolveDomain(long handle, String domain, boolean ipv4);

    private native void nativeSetBatchLogCallback(long handle, BatchLogCallback callback);

    private native void nativeSetRaceLogCallback(long handle, RaceLogCallback callback);

    private native void nativeSetBootstrapLogCallback(long handle, BootstrapLogCallback callback);

    private native String nativeStartFull(long handle, long fd);

    private native void nativeStopFull(long handle);

    private native void nativeReleaseTun(long handle);

    private native boolean nativeIsFullRunning(long handle);

    private native void nativeSetSocketProtector(long handle, SocketProtector callback);

    private native void nativeSetUidResolver(long handle, UIDResolver callback);

    private native void nativeSetAppUidResolver(long handle, AppUidResolver callback);

    private native void nativeSetTrafficCallback(long handle, TrafficCallback callback);

    private native void nativeSetBlockedUids(long handle, String uidsCsv);

    private native void nativeSetFilterHttp3(long handle, boolean enabled);

    private native void nativeSetBlockEncryptedDns(long handle, boolean enabled);

    private native void nativeSetTickIntervalMs(long handle, long millis);

    private native String nativeConfigureOutboundProxy(long handle, String configJson);

    private native void nativeSetOutboundProxyStatusCallback(long handle,
            OutboundProxyStatusCallback callback);

    private native String nativeStartStackMitm(long handle, String certDir);

    private native void nativeStopStackMitm(long handle);

    private native boolean nativeIsMitmActive(long handle);

    private native String nativeGetMitmCaCert(long handle, String certDir);

    private native void nativeSetMitmAllowedUids(long handle, String uidsCsv);

    private native void nativeSetHttpsBypassRules(long handle, String content);

    private native void nativeSetExtraPassthroughSuffixes(long handle, String content);

    private native void nativeClearMitmBlacklist(long handle);

    private native long nativeMitmBlacklistCount(long handle);

    private native void nativeSetCosmeticRules(long handle, String payload);

    private native void nativeSetRequestRules(long handle, String payload);

    private native void nativeSetHttpLogCallback(long handle, HttpLogCallback callback);
}
