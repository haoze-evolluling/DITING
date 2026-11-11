package com.haoze.diting.log

/// Picks this app's crashes out of the system crash buffer.
///
/// The buffer is shared by every app on the device, so only blocks that name the package are kept:
/// an exported log never carries another app's stack trace. The `logcat` process stays here; the
/// block splitting lives in the log kernel (`rust/diting-log-core/src/crash.rs`).
internal object CrashTail {
    fun select(lines: List<String>, packageName: String): List<String> {
        if (lines.isEmpty()) return emptyList()
        return LogNative.crashSelect(packageName, lines)
    }
}
