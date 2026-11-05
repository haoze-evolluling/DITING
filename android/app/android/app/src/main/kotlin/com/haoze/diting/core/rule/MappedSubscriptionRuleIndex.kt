package com.haoze.diting.core.rule

import android.util.Log
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteOrder
import java.nio.channels.FileChannel

/**
 * Compact, rebuildable subscription-rule cache. The SQLite rule tables remain the source of truth;
 * the DTRI file stays mmap-readable for the policy kernel, and its layout must not change.
 *
 * The writer is the Rust crate (`rust/diting-rule-core/src/dtri.rs`, reached through
 * [RustRuleIndexCompiler]); this class only writes the finished image and validates an existing
 * one, so a half-written or stale format is rejected before the engine ever maps it.
 */
internal class MappedSubscriptionRuleIndex private constructor(
    private val file: RandomAccessFile,
) : AutoCloseable {

    override fun close() = file.close()

    companion object {
        private const val MAGIC = 0x44545249 // DTRI
        private const val VERSION = 1
        private const val HEADER_INTS = 9
        private const val HEADER_SIZE = HEADER_INTS * 4
        private const val NODE_SIZE = 12
        private const val EDGE_SIZE = 12

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

        /** Validates the header and the section sizes; throws [IllegalArgumentException] when the
         *  image is not a DTRI file this build can read. */
        fun load(target: File): MappedSubscriptionRuleIndex {
            val file = RandomAccessFile(target, "r")
            try {
                val data = file.channel
                    .map(FileChannel.MapMode.READ_ONLY, 0, file.length())
                    .order(ByteOrder.BIG_ENDIAN)
                require(file.length() >= HEADER_SIZE && data.getInt(0) == MAGIC && data.getInt(4) == VERSION)
                val nodes = data.getInt(8)
                val edges = data.getInt(12)
                val sources = data.getInt(16)
                val bloomBits = data.getInt(20)
                val bloomBytes = data.getInt(24)
                val labelsBytes = data.getInt(28)
                val sourcesBytes = data.getInt(32)
                require(nodes > 0 && edges >= 0 && sources >= 0 && bloomBits > 0)
                val expectedLength = HEADER_SIZE.toLong() + bloomBytes + nodes.toLong() * NODE_SIZE +
                    edges.toLong() * EDGE_SIZE + labelsBytes + sourcesBytes
                require(expectedLength == file.length()) {
                    "DTRI sections do not cover the file"
                }
                return MappedSubscriptionRuleIndex(file)
            } catch (error: Throwable) {
                file.close()
                throw error
            }
        }
    }
}
