package com.haoze.diting.platform

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
                System.loadLibrary("diting_native")
                NotificationNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native notification kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        fun statsItems(raw: String, hasRaw: Boolean, legacySpeed: Boolean): List<String> =
            instance.statsItems(raw, hasRaw, legacySpeed)
                .lineSequence()
                .filter { it.isNotEmpty() }
                .toList()

        fun runningText(custom: String, modeDefault: String, fallback: String): String =
            instance.runningText(custom, modeDefault, fallback)

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
