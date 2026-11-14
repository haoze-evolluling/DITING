package com.haoze.diting.automation

/// Native state-event envelope builder for `rust/diting-event-core` (K9).
///
/// The frozen `STATE_CHANGED` JSON schema lives in Rust: this wrapper only forwards the live
/// values and returns the encoded envelope. The library is required, so a build that forgot
/// `python rust/build_android.py` throws instead of letting Kotlin emit a second, drifting shape.
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
                System.loadLibrary("diting_kernels")
                EventNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native event kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        /// Builds the frozen `state_changed` envelope; see `diting-event-core`.
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
