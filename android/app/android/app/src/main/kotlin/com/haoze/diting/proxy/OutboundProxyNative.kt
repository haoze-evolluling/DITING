package com.haoze.diting.proxy

/// Native outbound-proxy configuration kernel (`rust/diting-outbound-proxy-core`).
///
/// The engine rules (protocol, loopback host, port, credentials, scope) are the same functions the
/// Dart form uses; this class is the JNI face for the two places Kotlin still owns the storage:
/// normalizing SharedPreferences values and turning `packages` into the engine's `uids`.
///
/// The library is required: a build that forgot `python rust/build_android.py` throws here instead
/// of storing a value the engine would interpret differently.
internal class OutboundProxyNative private constructor() {
    external fun normalizeProtocol(value: String): String
    external fun normalizeScope(value: String): String
    external fun normalizeTargets(value: String): String
    external fun packages(proxyJson: String): String?
    external fun applyUids(proxyJson: String, uidsCsv: String): String

    companion object {
        private val instance: OutboundProxyNative by lazy {
            try {
                System.loadLibrary("diting_kernels")
                OutboundProxyNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native outbound proxy kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        /// `socks5` / `http`, anything else falling back to `socks5`.
        fun protocolOf(value: String?): String = instance.normalizeProtocol(value.orEmpty())

        /// `apps` exactly, anything else falling back to `all`.
        fun scopeOf(value: String?): String = instance.normalizeScope(value.orEmpty())

        /// Deduplicates, drops blanks and keeps the order; package names cannot contain newlines.
        fun targetsOf(values: List<String>): List<String> =
            instance.normalizeTargets(values.joinToString("\n"))
                .lineSequence()
                .filter { it.isNotEmpty() }
                .toList()

        /// Newline-separated package names, or null when the document has no per-app list.
        fun packagesOf(proxyJson: String): String? = instance.packages(proxyJson)

        /// Replaces `packages` with `uids`; malformed documents come back unchanged.
        fun withUids(proxyJson: String, uidsCsv: String): String =
            requireNotNull(instance.applyUids(proxyJson, uidsCsv)) {
                "native outbound proxy kernel rejected the per-app document"
            }
    }
}
