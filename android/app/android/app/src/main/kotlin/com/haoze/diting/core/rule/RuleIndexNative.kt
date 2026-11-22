package com.haoze.diting.core.rule

import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.nio.ByteBuffer

internal class RuleIndexNative private constructor() {
    external fun paths(datasetTag: Int): ByteArray?
    external fun dtriValidate(packed: ByteArray): ByteArray?
    external fun snapshotPlan(packed: ByteArray): ByteArray?
    external fun triePaths(packed: ByteArray): ByteArray?
    external fun appAllowlist(packed: ByteArray): ByteArray?
    external fun ruleFingerprint(packed: ByteArray): ByteArray?
    external fun rewriteRules(packed: ByteArray): ByteArray?

    companion object {
        private val instance: RuleIndexNative by lazy {
            try {
                System.loadLibrary("diting_native")
                RuleIndexNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native rule index helpers unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        fun paths(dataset: RuleDataset): RuleIndexPaths {
            val reader = RuleIndexPayload.Reader(
                requireNotNull(instance.paths(dataset.ordinal)) {
                    "native rule index layout rejected the dataset"
                },
            )
            return RuleIndexPaths(
                root = reader.string(),
                domain = reader.string(),
                hosts = reader.string(),
                block = reader.string(),
                blockImportant = reader.string(),
                allow = reader.string(),
                allowImportant = reader.string(),
            )
        }

        fun validate(header: ByteArray, fileLength: Long): RuleIndexValidation {
            val packed = RuleIndexPayload.pack { out ->
                out.writeInt(header.size)
                out.write(header)
                out.writeLong(fileLength)
            }
            val reader = RuleIndexPayload.Reader(
                requireNotNull(instance.dtriValidate(packed)) {
                    "native DTRI validator rejected the payload"
                },
            )
            val status = reader.u8()
            val expected = reader.i64()
            return when (status) {
                0 -> RuleIndexValidation.Ok
                1 -> RuleIndexValidation.Header
                2 -> RuleIndexValidation.Version
                3 -> RuleIndexValidation.Counts
                4 -> RuleIndexValidation.Sections(expected)
                else -> throw IllegalStateException("native DTRI validator returned no status")
            }
        }

        fun plan(block: RuleIndexHalf, allow: RuleIndexHalf): RuleIndexPlan {
            val packed = RuleIndexPayload.pack { out ->
                out.writeByte(block.normal.tag)
                out.writeByte(block.important.tag)
                out.writeByte(allow.normal.tag)
                out.writeByte(allow.important.tag)
            }
            val reader = RuleIndexPayload.Reader(
                requireNotNull(instance.snapshotPlan(packed)) {
                    "native rule index plan rejected the payload"
                },
            )
            val compiled = reader.u8() != 0
            val settled = reader.u8() != 0
            val blockNormal = reader.u8() != 0
            val blockImportant = reader.u8() != 0
            val allowNormal = reader.u8() != 0
            val allowImportant = reader.u8() != 0
            return RuleIndexPlan(
                compiled = compiled,
                settled = settled,
                block = RuleIndexHalfPlan(blockNormal, blockImportant, reader.u8() != 0),
                allow = RuleIndexHalfPlan(allowNormal, allowImportant, reader.u8() != 0),
            )
        }

        fun triePaths(indexDirectoryOk: Boolean, files: List<Pair<String, Pair<Boolean, Long>>>): List<String?> {
            require(files.size == 4) { "the DTRI layout has four artifacts" }
            val packed = RuleIndexPayload.pack { out ->
                out.writeByte(if (indexDirectoryOk) 1 else 0)
                out.writeInt(files.size)
                for ((path, state) in files) {
                    RuleIndexPayload.writeString(out, path)
                    out.writeByte(if (state.first) 1 else 0)
                    out.writeLong(state.second)
                }
            }
            val reader = RuleIndexPayload.Reader(
                requireNotNull(instance.triePaths(packed)) {
                    "native rule index layout rejected the trie listing"
                },
            )
            return List(4) { if (reader.u8() == 1) reader.string() else null }
        }

        fun appAllowlist(packages: List<Pair<String, List<String>>>): List<Pair<String, List<String>>> {
            val packed = RuleIndexPayload.pack { out ->
                out.writeInt(packages.size)
                for ((packageName, domains) in packages) {
                    RuleIndexPayload.writeString(out, packageName)
                    out.writeInt(domains.size)
                    domains.forEach { RuleIndexPayload.writeString(out, it) }
                }
            }
            val reader = RuleIndexPayload.Reader(
                requireNotNull(instance.appAllowlist(packed)) {
                    "native rule index plan rejected the per-app allowlist"
                },
            )
            return List(reader.count()) {
                val packageName = reader.string()
                packageName to List(reader.count()) { reader.string() }
            }
        }

        fun ruleFingerprint(parts: List<Pair<String, Triple<Long, Long, Long>?>>): String {
            val packed = RuleIndexPayload.pack { out ->
                out.writeInt(parts.size)
                for ((table, counts) in parts) {
                    RuleIndexPayload.writeString(out, table)
                    if (counts == null) {
                        out.writeByte(0)
                    } else {
                        out.writeByte(1)
                        out.writeLong(counts.first)
                        out.writeLong(counts.second)
                        out.writeLong(counts.third)
                    }
                }
            }
            val reader = RuleIndexPayload.Reader(
                requireNotNull(instance.ruleFingerprint(packed)) {
                    "native rule index plan rejected the fingerprint payload"
                },
            )
            return reader.string()
        }

        fun rewriteRules(rows: List<Pair<String, String>>): List<Pair<String, String>> {
            val packed = RuleIndexPayload.pack { out ->
                out.writeInt(rows.size)
                for ((pattern, target) in rows) {
                    RuleIndexPayload.writeString(out, pattern)
                    RuleIndexPayload.writeString(out, target)
                }
            }
            val reader = RuleIndexPayload.Reader(
                requireNotNull(instance.rewriteRules(packed)) {
                    "native rule index plan rejected the rewrite rows"
                },
            )
            return List(reader.count()) { reader.string() to reader.string() }
        }
    }
}

internal data class RuleIndexPaths(
    val root: String,
    val domain: String,
    val hosts: String,
    val block: String,
    val blockImportant: String,
    val allow: String,
    val allowImportant: String,
)

internal sealed interface RuleIndexValidation {
    data object Ok : RuleIndexValidation
    data object Header : RuleIndexValidation
    data object Version : RuleIndexValidation
    data object Counts : RuleIndexValidation
    data class Sections(val expectedLength: Long) : RuleIndexValidation
}

internal data class RuleIndexHalf(val normal: IndexOutcome, val important: IndexOutcome)

internal data class RuleIndexPlan(
    val compiled: Boolean,
    val settled: Boolean,
    val block: RuleIndexHalfPlan,
    val allow: RuleIndexHalfPlan,
)

internal data class RuleIndexHalfPlan(
    val normalUsable: Boolean,
    val importantUsable: Boolean,
    val specialRowsOnly: Boolean,
)

private object RuleIndexPayload {
    fun pack(write: (DataOutputStream) -> Unit): ByteArray {
        val buffer = ByteArrayOutputStream(64)
        val out = DataOutputStream(buffer)
        write(out)
        out.flush()
        return buffer.toByteArray()
    }

    fun writeString(out: DataOutputStream, value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        out.writeInt(bytes.size)
        out.write(bytes)
    }

    class Reader(payload: ByteArray) {
        private val buffer: ByteBuffer = ByteBuffer.wrap(payload)

        fun u8(): Int = buffer.get().toInt() and 0xFF

        fun i64(): Long = buffer.long

        fun count(): Int = buffer.int

        fun string(): String {
            val length = count()
            val bytes = ByteArray(length)
            buffer.get(bytes)
            return String(bytes, Charsets.UTF_8)
        }
    }
}
