package com.haoze.diting.core.rule

internal class RuleSnapshotNative private constructor() {
    external fun build(packed: ByteArray): ByteArray?

    companion object {
        private val instance: RuleSnapshotNative by lazy {
            try {
                System.loadLibrary("diting_native")
                RuleSnapshotNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native rule snapshot builder unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        fun buildSnapshotBytes(packed: ByteArray): ByteArray {
            val document = instance.build(packed)
            checkNotNull(document) { "native rule snapshot builder returned no document" }
            check(document.isNotEmpty()) { "native rule snapshot builder returned an empty document" }
            return document
        }
    }
}
