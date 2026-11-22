package com.haoze.diting.proxy

internal class OutboundProxyNative private constructor() {
    external fun normalizeProtocol(value: String): String
    external fun normalizeScope(value: String): String
    external fun normalizeTargets(value: String): String
    external fun packages(proxyJson: String): String?
    external fun applyUids(proxyJson: String, uidsCsv: String): String

    companion object {
        private val instance: OutboundProxyNative by lazy {
            try {
                System.loadLibrary("diting_native")
                OutboundProxyNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native outbound proxy kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        fun protocolOf(value: String?): String = instance.normalizeProtocol(value.orEmpty())

        fun scopeOf(value: String?): String = instance.normalizeScope(value.orEmpty())

        fun targetsOf(values: List<String>): List<String> =
            instance.normalizeTargets(values.joinToString("\n"))
                .lineSequence()
                .filter { it.isNotEmpty() }
                .toList()

        fun packagesOf(proxyJson: String): String? = instance.packages(proxyJson)

        fun withUids(proxyJson: String, uidsCsv: String): String =
            requireNotNull(instance.applyUids(proxyJson, uidsCsv)) {
                "native outbound proxy kernel rejected the per-app document"
            }
    }
}
