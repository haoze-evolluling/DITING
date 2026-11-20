package com.haoze.diting.automation

internal class EventNative private constructor() {
    external fun buildStateChanged(
        workMode: String,
        running: Boolean,
        reclaiming: Boolean,
        persisted: Boolean,
        startedAt: Long,
        pausedUntil: Long,
        error: String?,
    ): String

    companion object {
        private val instance: EventNative by lazy {
            try {
                System.loadLibrary("diting_native")
                EventNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native event kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        fun buildStateChanged(
            workMode: String,
            running: Boolean,
            reclaiming: Boolean,
            persisted: Boolean,
            startedAt: Long,
            pausedUntil: Long,
            error: String?,
        ): String = instance.buildStateChanged(
            workMode,
            running,
            reclaiming,
            persisted,
            startedAt,
            pausedUntil,
            error,
        )
    }
}
