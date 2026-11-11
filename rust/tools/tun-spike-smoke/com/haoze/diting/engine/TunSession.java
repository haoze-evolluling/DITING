package com.haoze.diting.engine;

/// The TUN session facade the engine will expose to `VpnService`, declared here exactly as Kotlin
/// will declare it.
///
/// The smoke test loads the host `libditing_tun_spike` and drives this class, so a renamed native, a
/// swapped argument order or a wrong callback signature fails on the host instead of on a phone.
public final class TunSession implements AutoCloseable {
    /// `VpnService.protect(int)`; `false` (or a thrown exception) must stop the dial.
    public interface Protector {
        boolean protect(long fd);
    }

    /// The batch callback the data plane uses; the payload is one JSON row.
    public interface PacketCallback {
        void onPacket(String json);
    }

    private long handle;

    public TunSession() {
        handle = nativeNew();
        if (handle == 0) {
            throw new IllegalStateException("the tun session handle is 0");
        }
    }

    public long handle() {
        return handle;
    }

    public void setProtector(Protector protector) {
        requireHandle();
        nativeSetProtector(handle, protector);
    }

    public void setCallback(PacketCallback callback) {
        requireHandle();
        nativeSetCallback(handle, callback);
    }

    /// Null on success, otherwise the error text.
    public String start(String target) {
        requireHandle();
        return nativeStart(handle, target);
    }

    public void stop() {
        requireHandle();
        nativeStop(handle);
    }

    /// Test hook: queue `count` synthetic packets, the way a TUN device would deliver them.
    public void feed(int count) {
        requireHandle();
        nativeFeed(handle, count);
    }

    /// Waits until `delivered` callbacks have arrived; `false` on timeout.
    public boolean waitForCallbacks(long delivered, long timeoutMs) {
        requireHandle();
        return nativeWaitForCallbacks(handle, delivered, timeoutMs);
    }

    public String getStats() {
        requireHandle();
        return nativeGetStats(handle);
    }

    @Override
    public void close() {
        if (handle != 0) {
            nativeFree(handle);
            handle = 0;
        }
    }

    private void requireHandle() {
        if (handle == 0) {
            throw new IllegalStateException("the tun session has been released");
        }
    }

    /// Smoke-test hook: calls the native with a raw handle, to prove a released handle is a lookup
    /// miss rather than a use-after-free.
    public static String statsForRawHandle(long handle) {
        return nativeGetStats(handle);
    }

    private static native long nativeNew();

    private static native void nativeFree(long handle);

    private static native void nativeSetProtector(long handle, Protector protector);

    private static native void nativeSetCallback(long handle, PacketCallback callback);

    private static native String nativeStart(long handle, String target);

    private static native void nativeStop(long handle);

    private static native void nativeFeed(long handle, int count);

    private static native boolean nativeWaitForCallbacks(long handle, long delivered, long timeoutMs);

    private static native String nativeGetStats(long handle);
}
