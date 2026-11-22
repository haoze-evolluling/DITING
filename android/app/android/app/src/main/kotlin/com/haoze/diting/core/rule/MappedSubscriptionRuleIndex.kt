package com.haoze.diting.core.rule

import android.util.Log
import java.io.File
import java.io.RandomAccessFile

internal class MappedSubscriptionRuleIndex private constructor(
    private val file: RandomAccessFile,
) : AutoCloseable {

    override fun close() = file.close()

    companion object {
        private const val HEADER_BYTES = 36

        fun compileAndLoad(
            target: File,
            forEachRule: ((EnabledRule) -> Unit) -> Unit
        ): MappedSubscriptionRuleIndex {
            target.parentFile?.mkdirs()
            val temp = File(target.parentFile, "${target.name}.${System.nanoTime()}.tmp")
            temp.delete()
            try {
                temp.outputStream().use { it.write(RustRuleIndexCompiler.compileDocument(forEachRule)) }
                if (target.exists() && !target.delete()) {
                    Log.w("MappedRuleIndex", "Unable to delete existing ${target.name} before replacement")
                }
                if (!temp.renameTo(target)) {
                    temp.copyTo(target, overwrite = true)
                    temp.delete()
                }
                return load(target)
            } finally {
                if (temp.exists()) {
                    temp.delete()
                }
            }
        }

        fun load(target: File): MappedSubscriptionRuleIndex {
            val file = RandomAccessFile(target, "r")
            try {
                val length = file.length()
                val header = ByteArray(minOf(length, HEADER_BYTES.toLong()).toInt())
                file.seek(0)
                file.readFully(header)
                when (val validation = RuleIndexNative.validate(header, length)) {
                    RuleIndexValidation.Ok -> Unit
                    RuleIndexValidation.Header ->
                        throw IllegalArgumentException("not a DTRI image this build can read")
                    RuleIndexValidation.Version ->
                        throw IllegalArgumentException("unsupported DTRI version")
                    RuleIndexValidation.Counts ->
                        throw IllegalArgumentException("DTRI header counts are impossible")
                    is RuleIndexValidation.Sections -> throw IllegalArgumentException(
                        "DTRI sections do not cover the file (expected ${validation.expectedLength})",
                    )
                }
                return MappedSubscriptionRuleIndex(file)
            } catch (error: Throwable) {
                file.close()
                throw error
            }
        }
    }
}
