package com.haoze.diting.express.cache

import com.haoze.diting.data.dao.DnsCacheDao
import com.haoze.diting.data.entity.DnsCacheEntity
import com.haoze.diting.express.engine.ExpressDnsEngine
import com.haoze.diting.express.dns.ExpressDnsMessageUtils
import com.haoze.diting.express.engine.ExpressPacketCodec
import com.haoze.diting.core.cache.DnsCachePolicy

/**
 * Cache adapter backed by Room [DnsCacheDao] and in-memory [SimpleLruCache].
 *
 * Implements [ExpressDnsEngine.ExpressDnsCache] for Express Mode. Stores defensive
 * copies of DNS response bytes, records TTL offsets in [DnsCacheEntity], and provides
 * thread-safe in-memory caching.
 */
class ExpressRoomDnsCache(
    private val dao: DnsCacheDao,
    private val cachePolicyProvider: () -> DnsCachePolicy
) : ExpressDnsEngine.ExpressDnsCache {

    internal class SimpleLruCache<K, V>(private val maxEntries: Int) {
        private val map = object : LinkedHashMap<K, V>(maxEntries, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<K, V>?): Boolean {
                return size > maxEntries
            }
        }

        @Synchronized
        fun get(key: K): V? = map[key]

        @Synchronized
        fun put(key: K, value: V) {
            map[key] = value
        }

        @Synchronized
        fun remove(key: K): V? = map.remove(key)

        @Synchronized
        fun clear() {
            map.clear()
        }

        @Synchronized
        fun size(): Int = map.size
    }

    private val memoryCache = SimpleLruCache<String, Pair<Long, ByteArray>>(500)

    fun clearMemory() {
        memoryCache.clear()
    }

    override suspend fun get(
        question: ExpressDnsMessageUtils.DnsQuestion,
        requestQuery: ByteArray
    ): ByteArray? {
        val policy = cachePolicyProvider()
        if (!policy.enabled) return null
        val normalizedName = question.name.lowercase().trimEnd('.')
        val key = "$normalizedName#${question.type}#${question.qclass}"
        val now = System.currentTimeMillis()

        val mem = memoryCache.get(key)
        if (mem != null) {
            val (expiresAt, response) = mem
            if (expiresAt > now) {
                val remainingTtl = ((expiresAt - now) / 1000L).coerceAtLeast(1L)
                val patched = ExpressPacketCodec.overwriteDnsPayloadTtl(response, remainingTtl)
                if (patched != null) return patched
            } else {
                memoryCache.remove(key)
            }
        }

        val entity = dao.get(key) ?: return null
        if (entity.expiresAt <= now) {
            dao.delete(key)
            return null
        }
        val remainingTtl = ((entity.expiresAt - now) / 1000L).coerceAtLeast(1L)
        val patched = ExpressPacketCodec.overwriteDnsPayloadTtl(entity.response, remainingTtl)
        if (patched != null) {
            memoryCache.put(key, entity.expiresAt to entity.response.copyOf())
            dao.recordHit(key, now)
            return patched
        }
        return null
    }

    override suspend fun put(
        question: ExpressDnsMessageUtils.DnsQuestion,
        response: ByteArray
    ) {
        val policy = cachePolicyProvider()
        if (!policy.enabled) return
        val normalizedName = question.name.lowercase().trimEnd('.')
        val key = "$normalizedName#${question.type}#${question.qclass}"
        val minTtl = ExpressPacketCodec.extractMinDnsTtl(response) ?: 300L
        val effectiveTtl = policy.effectiveTtlSeconds(minTtl)
        if (effectiveTtl <= 0L) return

        val now = System.currentTimeMillis()
        val expiresAt = now + effectiveTtl * 1000L
        val responseCopy = response.copyOf()
        memoryCache.put(key, expiresAt to responseCopy)

        val metadata = ExpressDnsMessageUtils.extractResponseTtlMetadata(response)
        val ttlOffsetsStr = metadata?.ttlOffsets?.joinToString(",") ?: ""

        val entity = DnsCacheEntity(
            key = key,
            queryName = normalizedName,
            queryType = question.type,
            queryClass = question.qclass,
            createdAt = now,
            expiresAt = expiresAt,
            lastHitAt = null,
            hitCount = 0,
            originalTtlSeconds = minTtl,
            ttlOffsets = ttlOffsetsStr,
            response = responseCopy,
            responseSize = responseCopy.size
        )
        dao.insert(entity)
    }
}
