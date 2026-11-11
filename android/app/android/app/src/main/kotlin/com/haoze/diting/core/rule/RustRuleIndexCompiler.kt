package com.haoze.diting.core.rule

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

/**
 * Native DTRI writer, the Rust side of `MappedSubscriptionRuleIndex.compileAndLoad`.
 *
 * The rules are packed into one byte array and handed to
 * `diting_rule_core`'s `Java_com_haoze_diting_core_rule_RustRuleIndexCompiler_compile`; the JNI
 * entry point returns the DTRI image (see `rust/diting-rule-core/src/dtri.rs` and the byte-parity
 * fixtures). The library is required: a build that forgot `python rust/build_android.py` fails
 * here with an [IllegalStateException] instead of quietly compiling a second writer in Kotlin.
 */
internal class RustRuleIndexCompiler private constructor() {
    external fun compile(packed: ByteArray): ByteArray?

    companion object {
        private val instance: RustRuleIndexCompiler by lazy {
            try {
                System.loadLibrary("diting_kernels")
                RustRuleIndexCompiler()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native rule index writer unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        /**
         * Compiles everything [forEachRule] yields into a DTRI image.
         *
         * DB/iterator errors propagate, and so does a rejected or empty image: there is no Kotlin
         * compiler to fall back to.
         */
        fun compileDocument(forEachRule: ((EnabledRule) -> Unit) -> Unit): ByteArray {
            val image = instance.compile(pack(forEachRule))
            checkNotNull(image) { "native rule index writer returned no image" }
            check(image.isNotEmpty()) { "native rule index writer returned an empty image" }
            return image
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
