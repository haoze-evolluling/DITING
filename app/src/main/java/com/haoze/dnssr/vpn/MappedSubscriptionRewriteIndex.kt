package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.EnabledRewriteRule
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.TreeMap
import kotlin.math.max

/** Memory-mapped reverse-domain trie for subscription rewrite rules. */
internal class MappedSubscriptionRewriteIndex private constructor(
    private val file: RandomAccessFile,
    private val data: ByteBuffer,
    private val nodeCount: Int,
    private val edgeCount: Int,
    private val answerCount: Int,
    private val bloomBitCount: Int,
    private val bloomOffset: Int,
    private val nodeOffset: Int,
    private val edgeOffset: Int,
    private val labelOffset: Int,
    private val targetIdOffset: Int,
    private val answerOffset: Int
) : AutoCloseable {

    fun find(domainInput: String): Set<RewriteAnswer> {
        val domain = domainInput.lowercase().trimEnd('.')
        if (domain.isEmpty() || !mightContainDomainOrParent(domain)) return emptySet()
        var candidate = domain
        while (true) {
            findExact(candidate)?.let { return it }
            val dot = candidate.indexOf('.')
            if (dot < 0) return emptySet()
            candidate = candidate.substring(dot + 1)
        }
    }

    fun findExact(domainInput: String): Set<RewriteAnswer>? {
        val domain = domainInput.lowercase().trimEnd('.')
        if (domain.isEmpty() || !mightContain(domain, 0, domain.length)) return null
        var node = 0
        var end = domain.length
        while (end > 0) {
            val dot = domain.lastIndexOf('.', end - 1)
            node = findChild(node, domain, dot + 1, end) ?: return null
            end = dot
        }
        val count = nodeInt(node, 1)
        return if (count > 0) readAnswers(nodeInt(node, 0), count) else null
    }

    private fun mightContainDomainOrParent(domain: String): Boolean {
        var start = 0
        while (start < domain.length) {
            if (mightContain(domain, start, domain.length)) return true
            val dot = domain.indexOf('.', start)
            if (dot < 0) break
            start = dot + 1
        }
        return false
    }

    private fun mightContain(value: String, start: Int, end: Int): Boolean {
        val (h1, h2) = hashes(value, start, end)
        repeat(BLOOM_HASHES) { index ->
            val bit = positiveMod(h1 + index.toLong() * h2, bloomBitCount.toLong()).toInt()
            if (data.get(bloomOffset + bit / 8).toInt() and (1 shl (bit % 8)) == 0) return false
        }
        return true
    }

    private fun findChild(node: Int, domain: String, start: Int, end: Int): Int? {
        val first = nodeInt(node, 2)
        val count = nodeInt(node, 3)
        for (index in first until first + count) {
            val base = edgeOffset + index * EDGE_SIZE
            val offset = data.getInt(base)
            val length = data.getInt(base + 4)
            if (length != end - start) continue
            var matches = true
            for (charIndex in 0 until length) {
                if ((data.get(labelOffset + offset + charIndex).toInt() and 0xff) != domain[start + charIndex].code) {
                    matches = false
                    break
                }
            }
            if (matches) return data.getInt(base + 8)
        }
        return null
    }

    private fun readAnswers(start: Int, count: Int): Set<RewriteAnswer> = buildSet {
        for (index in start until start + count) {
            val targetId = data.getInt(targetIdOffset + index * 4)
            if (targetId !in 0 until answerCount) continue
            var cursor = answerOffset
            repeat(targetId) { cursor += 8 + data.getInt(cursor) + data.getInt(cursor + 4) }
            val typeLength = data.getInt(cursor)
            val valueLength = data.getInt(cursor + 4)
            val type = readString(cursor + 8, typeLength)
            add(RewriteAnswer(type, readString(cursor + 8 + typeLength, valueLength)))
        }
    }

    private fun readString(offset: Int, length: Int): String {
        val bytes = ByteArray(length)
        data.duplicate().apply { position(offset); get(bytes) }
        return bytes.toString(Charsets.UTF_8)
    }

    private fun nodeInt(node: Int, field: Int): Int = data.getInt(nodeOffset + node * NODE_SIZE + field * 4)
    override fun close() = file.close()

    companion object {
        private const val MAGIC = 0x44525749 // DRWI
        private const val VERSION = 1
        private const val HEADER_INTS = 10
        private const val HEADER_SIZE = HEADER_INTS * 4
        private const val NODE_SIZE = 16
        private const val EDGE_SIZE = 12
        private const val BLOOM_HASHES = 7

        suspend fun compileAndLoad(
            target: File,
            forEachRule: suspend ((EnabledRewriteRule) -> Unit) -> Unit
        ): MappedSubscriptionRewriteIndex? {
            target.parentFile?.mkdirs()
            val temp = File(target.parentFile, target.name + ".tmp")
            temp.delete()
            if (!compile(temp, forEachRule)) {
                target.delete()
                return null
            }
            if (target.exists() && !target.delete()) error("Unable to replace ${target.name}")
            if (!temp.renameTo(target)) error("Unable to publish ${target.name}")
            return load(target)
        }

        fun load(target: File): MappedSubscriptionRewriteIndex {
            val file = RandomAccessFile(target, "r")
            try {
                val data = file.channel.map(FileChannel.MapMode.READ_ONLY, 0, file.length()).order(ByteOrder.BIG_ENDIAN)
                require(data.remaining() >= HEADER_SIZE && data.getInt(0) == MAGIC && data.getInt(4) == VERSION)
                val nodes = data.getInt(8)
                val edges = data.getInt(12)
                val answers = data.getInt(16)
                val bloomBits = data.getInt(20)
                val bloomBytes = data.getInt(24)
                val labelsBytes = data.getInt(28)
                val targetIdsBytes = data.getInt(32)
                val answersBytes = data.getInt(36)
                require(nodes > 0 && edges >= 0 && answers >= 0 && bloomBits > 0 && targetIdsBytes % 4 == 0)
                val nodeOffset = HEADER_SIZE + bloomBytes
                val edgeOffset = nodeOffset + nodes * NODE_SIZE
                val labelOffset = edgeOffset + edges * EDGE_SIZE
                val targetIdOffset = labelOffset + labelsBytes
                val answerOffset = targetIdOffset + targetIdsBytes
                require(answerOffset + answersBytes == data.limit())
                return MappedSubscriptionRewriteIndex(file, data, nodes, edges, answers, bloomBits, HEADER_SIZE, nodeOffset, edgeOffset, labelOffset, targetIdOffset, answerOffset)
            } catch (error: Throwable) {
                file.close()
                throw error
            }
        }

        private suspend fun compile(
            target: File,
            forEachRule: suspend ((EnabledRewriteRule) -> Unit) -> Unit
        ): Boolean {
            val root = RewriteBuildNode()
            var ruleCount = 0
            forEachRule { rule ->
                var node = root
                rule.pattern.lowercase().trimEnd('.').split('.').asReversed().forEach { label -> node = node.children.getOrPut(label) { RewriteBuildNode() } }
                node.answers += RewriteAnswer(rule.targetType, rule.targetValue)
                ruleCount++
            }
            if (ruleCount == 0) return false
            val nodes = mutableListOf<RewriteBuildNode>()
            fun assign(node: RewriteBuildNode) { node.index = nodes.size; nodes += node; node.children.values.forEach(::assign) }
            assign(root)
            val answers = nodes.flatMap { it.answers }.distinct().sortedWith(compareBy({ it.targetType }, { it.targetValue }))
            val answerIds = answers.withIndex().associate { it.value to it.index }
            val labels = ArrayList<Byte>()
            val edges = mutableListOf<RewriteFlatEdge>()
            val targetIds = mutableListOf<Int>()
            val flatNodes = nodes.map { node ->
                val targetStart = targetIds.size
                node.answers.sortedWith(compareBy({ it.targetType }, { it.targetValue })).forEach { targetIds += answerIds.getValue(it) }
                val firstEdge = edges.size
                node.children.forEach { (label, child) ->
                    val bytes = label.toByteArray(Charsets.UTF_8)
                    val offset = labels.size
                    bytes.forEach(labels::add)
                    edges += RewriteFlatEdge(offset, bytes.size, child.index)
                }
                RewriteFlatNode(targetStart, targetIds.size - targetStart, firstEdge, edges.size - firstEdge)
            }
            val bloomBits = max(64, ruleCount * 10)
            val bloom = ByteArray((bloomBits + 7) / 8)
            fun addBloom(domain: String) {
                val (h1, h2) = hashes(domain, 0, domain.length)
                repeat(BLOOM_HASHES) { index ->
                    val bit = positiveMod(h1 + index.toLong() * h2, bloomBits.toLong()).toInt()
                    bloom[bit / 8] = (bloom[bit / 8].toInt() or (1 shl (bit % 8))).toByte()
                }
            }
            fun collectBloom(node: RewriteBuildNode, reverseLabels: MutableList<String>) {
                if (node.answers.isNotEmpty()) addBloom(reverseLabels.asReversed().joinToString("."))
                node.children.forEach { (label, child) ->
                    reverseLabels += label
                    collectBloom(child, reverseLabels)
                    reverseLabels.removeAt(reverseLabels.lastIndex)
                }
            }
            collectBloom(root, mutableListOf())
            val answerBytes = answers.sumOf { 8 + it.targetType.toByteArray().size + it.targetValue.toByteArray().size }
            DataOutputStream(BufferedOutputStream(FileOutputStream(target))).use { out ->
                listOf(MAGIC, VERSION, flatNodes.size, edges.size, answers.size, bloomBits, bloom.size, labels.size, targetIds.size * 4, answerBytes).forEach(out::writeInt)
                out.write(bloom)
                flatNodes.forEach { out.writeInt(it.targetStart); out.writeInt(it.targetCount); out.writeInt(it.firstEdge); out.writeInt(it.edgeCount) }
                edges.forEach { out.writeInt(it.labelOffset); out.writeInt(it.labelLength); out.writeInt(it.child) }
                labels.forEach { out.writeByte(it.toInt()) }
                targetIds.forEach(out::writeInt)
                answers.forEach { answer ->
                    val type = answer.targetType.toByteArray(Charsets.UTF_8)
                    val value = answer.targetValue.toByteArray(Charsets.UTF_8)
                    out.writeInt(type.size); out.writeInt(value.size); out.write(type); out.write(value)
                }
            }
            return true
        }

        private fun hashes(value: String, start: Int, end: Int): Pair<Long, Long> {
            var h1 = -3750763034362895579L
            var h2 = -3750763034362895579L
            for (index in start until end) { val byte = value[index].code.toLong() and 0xff; h1 = (h1 xor byte) * 1099511628211L; h2 = h2 * 1099511628211L xor byte }
            return h1 to (h2 or 1L)
        }
        private fun positiveMod(value: Long, modulus: Long): Long = (value % modulus + modulus) % modulus
    }
}

private class RewriteBuildNode {
    val children = TreeMap<String, RewriteBuildNode>()
    val answers = linkedSetOf<RewriteAnswer>()
    var index = -1
}
private data class RewriteFlatNode(val targetStart: Int, val targetCount: Int, val firstEdge: Int, val edgeCount: Int)
private data class RewriteFlatEdge(val labelOffset: Int, val labelLength: Int, val child: Int)
