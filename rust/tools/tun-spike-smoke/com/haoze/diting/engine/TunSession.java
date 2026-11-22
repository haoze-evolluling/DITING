package com.haoze.diting.engine;

public final class TunSession implements AutoCloseable {
    public interface Protector {
        boolean protect(long fd);
    }

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

    public String start(String target) {
        requireHandle();
        return nativeStart(handle, target);
    }

    public void stop() {
        requireHandle();
        nativeStop(handle);
    }

    public void feed(int count) {
        requireHandle();
        nativeFeed(handle, count);
    }

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
