package com.haoze.diting.engine

/**
 * Native rule-test simulator, the Kotlin side of `rust/diting-engine/src/jni/rule_test.rs`.
 *
 * A stateless policy evaluation: it builds the policy snapshot from the `applyRuleSnapshot` document
 * the app already compiles and returns the verdict as JSON, so the "why blocked" answer is available
 * even when no tunnel is running. The library is required — a build that forgot
 * `python rust/build_android.py` fails the page instead of quietly not answering.
 */
internal class RuleTestNative private constructor() {
    external fun check(
        snapshotJson: String,
        rewriteJson: String,
        domain: String,
        app: String,
        qtype: Int,
    ): String?

    companion object {
        private val instance: RuleTestNative by lazy {
            NativeLoader.ensureLoaded()
            RuleTestNative()
        }

        /** Returns the JSON verdict; a null answer is a hard failure. */
        fun check(
            snapshotJson: String,
            rewriteJson: String,
            domain: String,
            app: String,
            qtype: Int,
        ): String {
            val document = instance.check(snapshotJson, rewriteJson, domain, app, qtype)
            checkNotNull(document) { "native rule test returned no document" }
            return document
        }
    }
}
