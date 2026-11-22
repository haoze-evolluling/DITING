package com.haoze.diting.core.rule

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream

internal class RustRuleIndexCompiler private constructor() {
    external fun compile(packed: ByteArray): ByteArray?

    companion object {
        private val instance: RustRuleIndexCompiler by lazy {
            try {
                System.loadLibrary("diting_native")
                RustRuleIndexCompiler()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native rule index writer unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        fun compileDocument(forEachRule: ((EnabledRule) -> Unit) -> Unit): ByteArray {
            val image = instance.compile(pack(forEachRule))
            checkNotNull(image) { "native rule index writer returned no image" }
            check(image.isNotEmpty()) { "native rule index writer returned an empty image" }
            return image
        }

        private fun pack(forEachRule: ((EnabledRule) -> Unit) -> Unit): ByteArray {
            val buffer = ByteArrayOutputStream(1 shl 20)
            val out = DataOutputStream(buffer)
            out.writeInt(0)
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
