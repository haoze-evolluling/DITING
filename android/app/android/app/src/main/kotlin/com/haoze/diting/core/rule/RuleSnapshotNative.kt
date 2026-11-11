package com.haoze.diting.core.rule

/**
 * Native snapshot builder, the Rust side of `RuleSnapshotStore.buildSnapshotJson`.
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
                System.loadLibrary("diting_kernels")
                RuleSnapshotNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native rule snapshot builder unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        /** Returns the JSON document; a null or empty answer is a hard failure. */
        fun buildSnapshot(packed: ByteArray): String {
            val document = instance.build(packed)
            checkNotNull(document) { "native rule snapshot builder returned no document" }
            check(document.isNotEmpty()) { "native rule snapshot builder returned an empty document" }
            return document.toString(Charsets.UTF_8)
        }
    }
}
