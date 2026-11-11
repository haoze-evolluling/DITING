package com.haoze.diting.platform

/// Native notification settings and detail-line formatter (`rust/diting-notification-core`).
///
/// Kotlin still reads SharedPreferences and the counters, and still draws the notification; the
/// ordered-item fallback, running-text chain and `1,234  ·  ↑ 1.5 MB/s` formatting come from here.
/// The library is required: a build without it throws instead of falling back to a second copy of
/// the rules.
internal class NotificationNative private constructor() {
    external fun statsItems(raw: String, hasRaw: Boolean, legacySpeed: Boolean): String
    external fun runningText(custom: String, modeDefault: String, fallback: String): String
    external fun compose(
        items: String,
        labelsJson: String,
        total: Long,
        passed: Long,
        filtered: Long,
        failed: Long,
        cached: Long,
        rewritten: Long,
        withSpeed: Boolean,
        txBps: Long,
        rxBps: Long,
    ): String?

    companion object {
        private val instance: NotificationNative by lazy {
            try {
                System.loadLibrary("diting_kernels")
                NotificationNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native notification kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        /// Ordered ids, newline-separated by the kernel.
        fun statsItems(raw: String, hasRaw: Boolean, legacySpeed: Boolean): List<String> =
            instance.statsItems(raw, hasRaw, legacySpeed)
                .lineSequence()
                .filter { it.isNotEmpty() }
                .toList()

        fun runningText(custom: String, modeDefault: String, fallback: String): String =
            instance.runningText(custom, modeDefault, fallback)

        /// Null when no item renders, so the caller keeps the body to the status text alone.
        fun compose(
            items: List<String>,
            labelsJson: String,
            total: Long,
            passed: Long,
            filtered: Long,
            failed: Long,
            cached: Long,
            rewritten: Long,
            withSpeed: Boolean,
            txBps: Long,
            rxBps: Long,
        ): String? = instance.compose(
            items.joinToString("\n"),
            labelsJson,
            total,
            passed,
            filtered,
            failed,
            cached,
            rewritten,
            withSpeed,
            txBps,
            rxBps,
        )
    }
}
