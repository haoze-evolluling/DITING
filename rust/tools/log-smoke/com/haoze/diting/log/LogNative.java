package com.haoze.diting.log;

/// Host-JVM copy of the `LogNative` declarations, used only by `LogSmoke` to prove that the
/// exported JNI symbols match the signatures Kotlin declares (name *and* argument order).
///
/// The body of every method is native, so a mismatch is an `UnsatisfiedLinkError` or a wrong answer
/// rather than a compile error; the Kotlin file is the real contract and this one is checked against
/// it by `python rust/verify.py --smoke`.
public final class LogNative {
    public native byte[] dnsBatch(long stats, int modeTag, byte[] packed, long nowMs);

    public native byte[] httpEvent(long stats, int modeTag, byte[] packed, long nowMs);

    public native byte[] raceRow(byte[] packed, long nowMs);

    public native byte[] bootstrapRow(byte[] packed, long nowMs);

    public native byte[] retentionPlan(byte[] packed);

    public native byte[] crashSelect(byte[] packed);

    public native long statsNew();

    public native void statsFree(long handle);

    public native void statsRequestReset(long handle);

    public native void statsRateReset(long handle);

    public native byte[] statsSnapshot(long handle);

    public native void rateTick(long handle, long tx, long rx, long nowMs);

    public native byte[] rateSnapshot(long handle, long nowMs);

    public native long trafficNew();

    public native void trafficFree(long handle);

    public native byte[] trafficOnTick(long handle, byte[] packed);

    public native byte[] trafficTake(long handle);

    public native boolean trafficRequeue(long handle, byte[] packed);

    public native long trafficBackoff(long handle, long nowMs);

    public native void trafficResetBackoff(long handle);

    public native boolean trafficInBackoff(long handle, long nowMs);

    public native int trafficClear(long handle);

    public native long healthNew();

    public native void healthFree(long handle);

    public native byte[] healthDropped(long handle, byte[] packed, long nowMs);

    public native byte[] healthOpenFailure(long handle, String databaseName, String cause, long nowMs);

    public native byte[] healthWarn(long handle, String message, String cause, long nowMs);

    public native byte[] healthSnapshot(long handle);

    public native long attrNew();

    public native void attrFree(long handle);

    public native byte[] attrUidLookup(long handle, byte[] packed, long nowMs);

    public native boolean attrUidStore(long handle, byte[] packed, int uid, long nowMs);

    public native byte[] attrPackageLookup(long handle, int uid);

    public native void attrPackageStore(long handle, int uid, String name);

    public native void attrClear(long handle);

    public native long queueNew(int settingsTag);

    public native void queueFree(long handle);

    public native byte[] queueSubmit(long handle, byte[] packed, long nowMs);

    public native byte[] queueTake(long handle);

    public native int queueRequeue(long handle, byte[] packed);

    public native long queueBackoff(long handle, long nowMs);

    public native void queueResetBackoff(long handle);

    public native long queueRetryWait(long handle, long nowMs);

    public native boolean queueInBackoff(long handle, long nowMs);

    public native boolean queueMissingLatched(long handle, long nowMs);

    public native void queueLatchMissing(long handle, long nowMs);

    public native void queueMarkClosed(long handle);

    public native boolean queueIsClosed(long handle);

    public native int queueClose(long handle);

    public native int queuePendingLen(long handle);

    public native byte[] storeIndex(byte[] packed);

    public native byte[] storeDocument(byte[] packed);

    public native byte[] capturePlan(int pid);

    public native long captureSessionNew();

    public native void captureSessionFree(long handle);

    public native byte[] captureLine(long handle, byte[] packed);

    public native byte[] mirrorLayout();

    public native byte[] mirrorRows(byte[] packed);
}
