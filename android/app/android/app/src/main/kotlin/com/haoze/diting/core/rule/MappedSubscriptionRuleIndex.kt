package com.haoze.diting.core.rule

import android.util.Log
import java.io.File
import java.io.RandomAccessFile

/**
 * Compact, rebuildable subscription-rule cache. The SQLite rule tables remain the source of truth;
 * the DTRI file stays mmap-readable for the policy kernel, and its layout must not change.
 *
 * The writer is the Rust crate (`rust/diting-rule-core/src/dtri.rs`, reached through
 * [RustRuleIndexCompiler]); the header checks (`MappedSubscriptionRuleIndex.load`) live in the same
 * crate, so a half-written or stale format is rejected before the engine ever maps it and there is
 * no second reader of the format in Kotlin.
 */
internal class MappedSubscriptionRuleIndex private constructor(
    private val file: RandomAccessFile,
) : AutoCloseable {

    override fun close() = file.close()

    companion object {
        /// The header the validator peeks at: nine `u32`s.
        private const val HEADER_BYTES = 36

        /**
         * Compiles everything [forEachRule] yields, replaces [target] with the finished image and
         * returns the validated handle. A compile or a bad image throws: there is no second
         * compiler to fall back to, and the caller treats the failure as "no trie this round".
         */
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

        /** Validates the header and the section sizes through the kernel; throws
         *  [IllegalArgumentException] when the image is not a DTRI file this build can read. */
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
