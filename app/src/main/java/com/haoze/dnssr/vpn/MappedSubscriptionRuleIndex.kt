package com.haoze.dnssr.vpn

import android.util.Log
import com.haoze.dnssr.data.dao.EnabledBlockRule
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
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
    private val sourceOffset: Int,
    private val sourceNames: Array<String>
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
        var low = first
        var high = first + count - 1
        while (low <= high) {
            val mid = (low + high) ushr 1
            val cmp = compareEdge(mid, domain, start, end)
            when {
                cmp < 0 -> high = mid - 1
                cmp > 0 -> low = mid + 1
                else -> return data.getInt(edgeOffset + mid * EDGE_SIZE + 8)
            }
        }
        return null
    }

    private fun compareEdge(edgeIndex: Int, domain: String, start: Int, end: Int): Int {
        val base = edgeOffset + edgeIndex * EDGE_SIZE
        val offset = data.getInt(base)
        val length = data.getInt(base + 4)
        val targetLen = end - start
        val minLen = minOf(targetLen, length)
        for (i in 0 until minLen) {
            val cTarget = domain[start + i].code
            val cEdge = data.get(labelOffset + offset + i).toInt() and 0xff
            if (cTarget != cEdge) {
                return cTarget - cEdge
            }
        }
        return targetLen - length
    }

    private fun nodeInt(node: Int, field: Int): Int = data.getInt(nodeOffset + node * NODE_SIZE + field * 4)

    private fun readSource(target: Int): String? {
        if (target in sourceNames.indices) return sourceNames[target]
        return null
    }

    override fun close() = file.close()

    companion object {
        private const val TAG = "MappedRuleIndex"
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
            val temp = File(target.parentFile, "${target.name}.${System.nanoTime()}.tmp")
            temp.delete()
            try {
                if (!compile(temp, forEachRule)) {
                    target.delete()
                    return null
                }
                if (target.exists() && !target.delete()) {
                    Log.w(TAG, "Unable to delete existing ${target.name} before replacement")
                }
                if (!temp.renameTo(target)) {
                    temp.copyTo(target, overwrite = true)
                    temp.delete()
                }
                return load(target)
            } catch (e: Throwable) {
                Log.e(TAG, "Failed to compile and load ${target.name}", e)
                throw e
            } finally {
                if (temp.exists()) {
                    temp.delete()
                }
            }
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

                var cursor = sourceOffset
                val sourceNames = Array(sources) {
                    val length = data.getInt(cursor)
                    cursor += 4
                    val bytes = ByteArray(length)
                    val copy = data.duplicate()
                    copy.position(cursor)
                    copy.get(bytes)
                    cursor += length
                    bytes.toString(Charsets.UTF_8)
                }

                return MappedSubscriptionRuleIndex(
                    file, data, nodes, edges, sources, bloomBits, HEADER_SIZE,
                    nodeOffset, edgeOffset, labelOffset, sourceOffset, sourceNames
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
                if (rule.isWildcard || rule.pattern.contains('*') || !rule.appScope.isNullOrEmpty() || rule.appInverted) {
                    return@forEachRule
                }
                var node = root
                val pattern = rule.pattern.lowercase().trimEnd('.')
                var end = pattern.length
                while (end > 0) {
                    val dot = pattern.lastIndexOf('.', end - 1)
                    val label = pattern.substring(dot + 1, end)
                    node = node.children.getOrPut(label) { BuildNode() }
                    end = dot
                }
                node.source = node.source?.let { minOf(it, rule.source) } ?: rule.source
                node.pattern = pattern
                sources += rule.source
                ruleCount++
            }
            val nodes = ArrayList<BuildNode>()
            fun assign(node: BuildNode) {
                node.index = nodes.size
                nodes.add(node)
                val sortedChildren = if (node.children.size > 1) {
                    node.children.entries.sortedBy { it.key }.map { it.value }
                } else {
                    node.children.values
                }
                sortedChildren.forEach(::assign)
            }
            assign(root)
            val sourceIds = sources.withIndex().associate { it.value to it.index }
            val labels = ByteArrayOutputStream()
            val edges = ArrayList<FlatEdge>()
            val flatNodes = ArrayList<FlatNode>(nodes.size)
            for (node in nodes) {
                val first = edges.size
                val sortedEntries = if (node.children.size > 1) {
                    node.children.entries.sortedBy { it.key }
                } else {
                    node.children.entries
                }
                for ((label, child) in sortedEntries) {
                    val bytes = label.toByteArray(Charsets.UTF_8)
                    val offset = labels.size()
                    labels.write(bytes)
                    edges.add(FlatEdge(offset, bytes.size, child.index))
                }
                flatNodes.add(FlatNode(node.source?.let(sourceIds::get) ?: -1, first, edges.size - first))
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
            fun collectBloom(node: BuildNode) {
                node.pattern?.let { addBloom(it) }
                node.children.values.forEach(::collectBloom)
            }
            collectBloom(root)
            val sourceBytes = sources.sumOf { 4 + it.toByteArray(Charsets.UTF_8).size }
            DataOutputStream(BufferedOutputStream(FileOutputStream(target))).use { out ->
                listOf(MAGIC, VERSION, flatNodes.size, edges.size, sources.size, bloomBits, bloom.size, labels.size(), sourceBytes)
                    .forEach(out::writeInt)
                out.write(bloom)
                flatNodes.forEach { out.writeInt(it.source); out.writeInt(it.firstEdge); out.writeInt(it.edgeCount) }
                edges.forEach { out.writeInt(it.labelOffset); out.writeInt(it.labelLength); out.writeInt(it.child) }
                labels.writeTo(out)
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
    val children = HashMap<String, BuildNode>()
    var source: String? = null
    var pattern: String? = null
    var index: Int = -1
}

private data class FlatNode(val source: Int, val firstEdge: Int, val edgeCount: Int)
private data class FlatEdge(val labelOffset: Int, val labelLength: Int, val child: Int)
