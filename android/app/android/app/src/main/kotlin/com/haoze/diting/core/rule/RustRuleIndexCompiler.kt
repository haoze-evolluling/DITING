package com.haoze.diting.core.rule

import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

/**
 * Native DTRI writer, the Rust side of `MappedSubscriptionRuleIndex.compile`.
 *
 * The rules are packed into one byte array and handed to
 * `diting_rule_core`'s `Java_com_haoze_diting_core_rule_RustRuleIndexCompiler_compile`; the JNI
 * entry point returns the exact same file the Kotlin compiler writes (see
 * `rust/diting-rule-core/src/dtri.rs` and the byte-parity fixtures). Anything unexpected — a build
 * without the library, an older `.so`, a malformed result — returns null and the caller runs the
 * original Kotlin compiler, so rule snapshots keep working exactly as before.
 */
internal class RustRuleIndexCompiler private constructor() {
    external fun compile(packed: ByteArray): ByteArray?

    companion object {
        private const val TAG = "RustRuleIndex"

        /** Set once a call fails: retrying per snapshot would only repeat the failure. */
        @Volatile
        private var disabled = false

        private val instance: RustRuleIndexCompiler? by lazy {
            runCatching {
                System.loadLibrary("diting_rule_core")
                RustRuleIndexCompiler()
            }.onFailure {
                Log.i(TAG, "native rule index writer unavailable, using the Kotlin compiler: ${it.message}")
            }.getOrNull()
        }

        /**
         * Compiles everything [forEachRule] yields into a DTRI image, or returns null when the
         * caller should compile with Kotlin instead. DB/iterator errors propagate: they are not a
         * native-path problem, and the Kotlin compiler would fail the same way.
         */
        fun compileDocument(forEachRule: ((EnabledRule) -> Unit) -> Unit): ByteArray? {
            if (disabled) return null
            val compiler = instance ?: return null
            val packed = pack(forEachRule)
            return try {
                compiler.compile(packed)?.takeIf { it.isNotEmpty() }
            } catch (error: Throwable) {
                disabled = true
                Log.w(TAG, "native rule index compile failed, using the Kotlin compiler for this process", error)
                null
            }
        }

        /**
         * `u32 count | count * (u32 patternLen, pattern, u32 sourceLen, source, u8 flags,
         * u32 appScopeLen | u32::MAX, appScope, u32 denyallowLen | u32::MAX, denyallow,
         * u32 dnsTypeLen | u32::MAX, dnsType)`; flags are wildcard/appInverted/regex in bits 0-2.
         *
         * `important` is not packed: the loaders already split the normal and important tries, and
         * the trie never looks at it.
         */
        private fun pack(forEachRule: ((EnabledRule) -> Unit) -> Unit): ByteArray {
            val buffer = ByteArrayOutputStream(1 shl 20)
            val out = DataOutputStream(buffer)
            out.writeInt(0) // rule count, patched after the callback finishes
            var count = 0
            forEachRule { rule ->
                writeString(out, rule.pattern)
                writeString(out, rule.source)
                var flags = 0
                if (rule.isWildcard) flags = flags or 1
                if (rule.appInverted) flags = flags or 2
                if (rule.isRegex) flags = flags or 4
                out.writeByte(flags)
                writeOptionalString(out, rule.appScope)
                writeOptionalString(out, rule.denyallow)
                writeOptionalString(out, rule.dnsType)
                count++
            }
            out.flush()
            val bytes = buffer.toByteArray()
            bytes[0] = (count ushr 24).toByte()
            bytes[1] = (count ushr 16).toByte()
            bytes[2] = (count ushr 8).toByte()
            bytes[3] = count.toByte()
            return bytes
        }

        private fun writeString(out: DataOutputStream, value: String) {
            val bytes = value.toByteArray(Charsets.UTF_8)
            out.writeInt(bytes.size)
            out.write(bytes)
        }

        private fun writeOptionalString(out: DataOutputStream, value: String?) {
            if (value == null) {
                out.writeInt(-1)
            } else {
                writeString(out, value)
            }
        }
    }
}
