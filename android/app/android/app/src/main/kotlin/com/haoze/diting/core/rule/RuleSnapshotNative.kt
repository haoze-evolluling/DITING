package com.haoze.diting.core.rule

/**
 * Native snapshot builder, the Rust side of `RuleSnapshotStore.buildSnapshot`.
 *
 * The request layout is documented on [RuleSnapshotPayload]; `diting_rule_core`'s JNI entry point
 * returns the `applyRuleSnapshot` JSON document (see `rust/diting-rule-core/src/snapshot.rs`). The
 * library is required: a build that forgot `python rust/build_android.py` fails the snapshot build
 * instead of quietly running a second classifier in Kotlin.
 */
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

        /**
         * Returns the JSON document as UTF-8 bytes; a null or empty answer is a hard failure.
         *
         * The engine takes these bytes directly, so a multi-megabyte snapshot is never widened to
         * a Java `String` and narrowed back to modified UTF-8 on the way in.
         */
        fun buildSnapshotBytes(packed: ByteArray): ByteArray {
            val document = instance.build(packed)
            checkNotNull(document) { "native rule snapshot builder returned no document" }
            check(document.isNotEmpty()) { "native rule snapshot builder returned an empty document" }
            return document
        }
    }
}
