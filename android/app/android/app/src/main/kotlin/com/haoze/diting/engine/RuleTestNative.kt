package com.haoze.diting.engine

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
