package com.haoze.dnssr.vpn

import com.haoze.dnssr.data.dao.EnabledBlockRule
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
import java.util.TreeMap
import java.util.TreeSet
import kotlin.math.max

/** Compact, rebuildable subscription-rule cache. Room remains the source of truth. */
internal class MappedSubscriptionRuleIndex private constructor(
    private val file: RandomAccessFile,
    private val data: ByteBuffer,
    private val nodeCount: Int,
    private val edgeCount: Int,
    private val sourceCount: Int,
    private val bloomBitCount: Int,
    private val bloomOffset: Int,
    private val nodeOffset: Int,
    private val edgeOffset: Int,
    private val labelOffset: Int,
    private val sourceOffset: Int
) : AutoCloseable {

    fun find(domainInput: String, overrides: Map<String, String?> = emptyMap()): String? {
        val domain = domainInput.lowercase().trimEnd('.')
        if (domain.isEmpty() || !mightContainDomainOrParent(domain)) return null
        var node = 0
        var end = domain.length
        while (end > 0) {
            val dot = domain.lastIndexOf('.', end - 1)
            val start = dot + 1
            val child = findChild(node, domain, start, end) ?: return null
            node = child
            val pattern = domain.substring(start)
            if (overrides.containsKey(pattern)) {
                overrides[pattern]?.let { return it }
            } else {
                val terminalSource = nodeInt(node, 0)
                if (terminalSource >= 0) return readSource(terminalSource)
            }
            end = dot
        }
        return null
    }

    private fun mightContainDomainOrParent(domain: String): Boolean {
        var start = 0
        while (start < domain.length) {
            val (h1, h2) = hashes(domain, start, domain.length)
            var possible = true
            repeat(BLOOM_HASHES) { index ->
                val bit = positiveMod(h1 + index.toLong() * h2, bloomBitCount.toLong()).toInt()
                val value = data.get(bloomOffset + bit / 8).toInt()
                if (value and (1 shl (bit % 8)) == 0) possible = false
            }
            if (possible) return true
            val dot = domain.indexOf('.', start)
            if (dot < 0) break
            start = dot + 1
        }
        return false
    }

    private fun findChild(node: Int, domain: String, start: Int, end: Int): Int? {
        val first = nodeInt(node, 1)
        val count = nodeInt(node, 2)
        for (index in first until first + count) {
            val base = edgeOffset + index * EDGE_SIZE
            val offset = data.getInt(base)
            val length = data.getInt(base + 4)
            if (length != end - start) continue
            var matches = true
            for (charIndex in 0 until length) {
                if (data.get(labelOffset + offset + charIndex).toInt() and 0xff != domain[start + charIndex].code) {
                    matches = false
                    break
                }
            }
            if (matches) return data.getInt(base + 8)
        }
        return null
    }

    private fun nodeInt(node: Int, field: Int): Int = data.getInt(nodeOffset + node * NODE_SIZE + field * 4)

    private fun readSource(target: Int): String? {
        if (target !in 0 until sourceCount) return null
        var cursor = sourceOffset
        repeat(sourceCount) { index ->
            val length = data.getInt(cursor)
            cursor += 4
            if (index == target) {
                val bytes = ByteArray(length)
                val copy = data.duplicate()
                copy.position(cursor)
                copy.get(bytes)
                return bytes.toString(Charsets.UTF_8)
            }
            cursor += length
        }
        return null
    }

    override fun close() = file.close()

    companion object {
        private const val MAGIC = 0x44545249 // DTRI
        private const val VERSION = 1
        private const val HEADER_INTS = 9
        private const val HEADER_SIZE = HEADER_INTS * 4
        private const val NODE_SIZE = 12
        private const val EDGE_SIZE = 12
        private const val BLOOM_HASHES = 7

        suspend fun compileAndLoad(
            target: File,
            forEachRule: suspend ((EnabledBlockRule) -> Unit) -> Unit
        ): MappedSubscriptionRuleIndex? {
            target.parentFile?.mkdirs()
            val temp = File(target.parentFile, target.name + ".tmp")
            if (!compile(temp, forEachRule)) {
                target.delete()
                return null
            }
            if (target.exists() && !target.delete()) error("Unable to replace ${target.name}")
            if (!temp.renameTo(target)) error("Unable to publish ${target.name}")
            return load(target)
        }

        fun load(target: File): MappedSubscriptionRuleIndex {
            val file = RandomAccessFile(target, "r")
            try {
                val data = file.channel.map(FileChannel.MapMode.READ_ONLY, 0, file.length()).order(ByteOrder.BIG_ENDIAN)
                require(data.remaining() >= HEADER_SIZE && data.getInt(0) == MAGIC && data.getInt(4) == VERSION)
                val nodes = data.getInt(8)
                val edges = data.getInt(12)
                val sources = data.getInt(16)
                val bloomBits = data.getInt(20)
                val bloomBytes = data.getInt(24)
                val labelsBytes = data.getInt(28)
                val sourcesBytes = data.getInt(32)
                require(nodes > 0 && edges >= 0 && sources >= 0 && bloomBits > 0)
                val nodeOffset = HEADER_SIZE + bloomBytes
                val edgeOffset = nodeOffset + nodes * NODE_SIZE
                val labelOffset = edgeOffset + edges * EDGE_SIZE
                val sourceOffset = labelOffset + labelsBytes
                require(sourceOffset + sourcesBytes == data.limit())
                return MappedSubscriptionRuleIndex(
                    file, data, nodes, edges, sources, bloomBits, HEADER_SIZE,
                    nodeOffset, edgeOffset, labelOffset, sourceOffset
                )
            } catch (error: Throwable) {
                file.close()
                throw error
            }
        }

        private suspend fun compile(
            target: File,
            forEachRule: suspend ((EnabledBlockRule) -> Unit) -> Unit
        ): Boolean {
            val root = BuildNode()
            val sources = TreeSet<String>()
            var ruleCount = 0
            forEachRule { rule ->
                var node = root
                rule.pattern.lowercase().trimEnd('.').split('.').asReversed().forEach { label ->
                    node = node.children.getOrPut(label) { BuildNode() }
                }
                node.source = node.source?.let { minOf(it, rule.source) } ?: rule.source
                sources += rule.source
                ruleCount++
            }
            if (ruleCount == 0) return false
            val nodes = mutableListOf<BuildNode>()
            fun assign(node: BuildNode) {
                node.index = nodes.size
                nodes += node
                node.children.values.forEach(::assign)
            }
            assign(root)
            val sourceIds = sources.withIndex().associate { it.value to it.index }
            val labels = ArrayList<Byte>()
            val edges = mutableListOf<FlatEdge>()
            val flatNodes = nodes.map { node ->
                val first = edges.size
                node.children.forEach { (label, child) ->
                    val bytes = label.toByteArray(Charsets.UTF_8)
                    val offset = labels.size
                    bytes.forEach(labels::add)
                    edges += FlatEdge(offset, bytes.size, child.index)
                }
                FlatNode(node.source?.let(sourceIds::get) ?: -1, first, edges.size - first)
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
            fun collectBloom(node: BuildNode, reverseLabels: MutableList<String>) {
                if (node.source != null) addBloom(reverseLabels.asReversed().joinToString("."))
                node.children.forEach { (label, child) ->
                    reverseLabels += label
                    collectBloom(child, reverseLabels)
                    reverseLabels.removeAt(reverseLabels.lastIndex)
                }
            }
            collectBloom(root, mutableListOf())
            val sourceBytes = sources.sumOf { 4 + it.toByteArray(Charsets.UTF_8).size }
            DataOutputStream(BufferedOutputStream(FileOutputStream(target))).use { out ->
                listOf(MAGIC, VERSION, flatNodes.size, edges.size, sources.size, bloomBits, bloom.size, labels.size, sourceBytes)
                    .forEach(out::writeInt)
                out.write(bloom)
                flatNodes.forEach { out.writeInt(it.source); out.writeInt(it.firstEdge); out.writeInt(it.edgeCount) }
                edges.forEach { out.writeInt(it.labelOffset); out.writeInt(it.labelLength); out.writeInt(it.child) }
                labels.forEach { out.writeByte(it.toInt()) }
                sources.forEach { source ->
                    val bytes = source.toByteArray(Charsets.UTF_8)
                    out.writeInt(bytes.size)
                    out.write(bytes)
                }
            }
            return true
        }

        private fun hashes(value: String, start: Int, end: Int): Pair<Long, Long> {
            var h1 = -3750763034362895579L
            var h2 = -3750763034362895579L
            for (index in start until end) {
                val byte = value[index].code.toLong() and 0xff
                h1 = (h1 xor byte) * 1099511628211L
                h2 = h2 * 1099511628211L xor byte
            }
            return h1 to (h2 or 1L)
        }

        private fun positiveMod(value: Long, modulus: Long): Long = (value % modulus + modulus) % modulus
    }
}

private class BuildNode {
    val children = TreeMap<String, BuildNode>()
    var source: String? = null
    var index: Int = -1
}

private data class FlatNode(val source: Int, val firstEdge: Int, val edgeCount: Int)
private data class FlatEdge(val labelOffset: Int, val labelLength: Int, val child: Int)
