package com.haoze.dnssr.vpn.cache

import com.haoze.dnssr.data.dao.DnsCacheDao
import com.haoze.dnssr.data.dao.DnsCacheHitUpdate
import com.haoze.dnssr.data.entity.DnsCacheEntity
import com.haoze.dnssr.vpn.DnsMessageUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlin.math.ceil
import kotlin.math.max

data class DnsCacheResult(
    val response: ByteArray,
    val cached: Boolean,
    val stale: Boolean = false
)

class DnsResponseCache(
    private val dao: DnsCacheDao,
    initialPolicy: DnsCachePolicy,
    private val scope: CoroutineScope,
    private val maxEntries: Int = DEFAULT_MAX_ENTRIES,
    shardCount: Int = DEFAULT_SHARD_COUNT
) {
    @Volatile
    private var policy: DnsCachePolicy = initialPolicy

    private val shards = List(shardCount.coerceAtLeast(1)) {
        CacheShard(max(1, ceil(maxEntries.toDouble() / shardCount.coerceAtLeast(1)).toInt()))
    }
    private val inFlightMutex = Mutex()
    private val inFlight = HashMap<String, Deferred<ByteArray>>()
    private val pendingHitMutex = Mutex()
    private val pendingHits = HashMap<String, PendingHit>()
    private var pendingHitFlushJob: Job? = null
    private val pendingWriteMutex = Mutex()
    private val pendingWrites = LinkedHashMap<String, DnsCacheEntity>()
    private var pendingWriteFlushJob: Job? = null

    fun updatePolicy(policy: DnsCachePolicy) {
        this.policy = policy
    }

    suspend fun resolve(
        question: DnsMessageUtils.DnsQuestion,
        requestQuery: ByteArray,
        resolver: suspend () -> ByteArray
    ): DnsCacheResult {
        val currentPolicy = policy
        if (!currentPolicy.enabled) {
            return DnsCacheResult(resolver(), cached = false)
        }

        get(question, requestQuery, allowStale = false)?.let {
            return DnsCacheResult(it, cached = true)
        }

        val cacheKey = DnsCacheKey.fromQuestion(question)
        return coroutineScope {
            var leader = false
            val deferred = inFlightMutex.withLock {
                inFlight[cacheKey.storageKey] ?: async {
                    resolver()
                }.also {
                    inFlight[cacheKey.storageKey] = it
                    leader = true
                }
            }

            try {
                val resolved = deferred.await()
                if (leader && DnsMessageUtils.isSuccessResponse(resolved)) {
                    put(cacheKey, resolved)
                }
                DnsCacheResult(
                    response = DnsMessageUtils.withTransactionId(resolved, requestQuery),
                    cached = false
                )
            } catch (e: Exception) {
                val stale = if (currentPolicy.staleFallbackEnabled) {
                    get(question, requestQuery, allowStale = true)
                } else {
                    null
                }
                if (stale != null) {
                    DnsCacheResult(stale, cached = false, stale = true)
                } else {
                    throw e
                }
            } finally {
                if (leader) {
                    inFlightMutex.withLock {
                        if (inFlight[cacheKey.storageKey] === deferred) {
                            inFlight.remove(cacheKey.storageKey)
                        }
                    }
                }
            }
        }
    }

    suspend fun warmUp() {
        val now = System.currentTimeMillis()
        val rows = dao.getUnexpired(now, maxEntries)
        shards.forEach { it.clear() }
        rows.forEach { entity ->
            val entry = entity.toEntry(policy)
            shardFor(entity.key).put(entity.key, entry)
        }
        dao.deleteExpired(now)
    }

    suspend fun clear() {
        clearMemory()
        clearPendingWrites()
        clearPendingHits()
        dao.clearAll()
    }

    suspend fun clearMemory() {
        shards.forEach { it.clear() }
    }

    private suspend fun get(
        question: DnsMessageUtils.DnsQuestion,
        requestQuery: ByteArray,
        allowStale: Boolean
    ): ByteArray? {
        val cacheKey = DnsCacheKey.fromQuestion(question)
        val now = System.currentTimeMillis()
        val shard = shardFor(cacheKey.storageKey)

        val memoryEntry = shard.get(cacheKey.storageKey)
        if (memoryEntry != null) {
            return materialize(memoryEntry, requestQuery, now, allowStale) ?: run {
                if (!allowStale && shouldDeleteUnavailable(memoryEntry, now)) {
                    removeExpired(cacheKey.storageKey, shard)
                }
                null
            }
        }

        val entity = dao.get(cacheKey.storageKey) ?: return null
        val entry = entity.toEntry(policy)
        val response = materialize(entry, requestQuery, now, allowStale)
        if (response == null) {
            if (!allowStale && shouldDeleteUnavailable(entry, now)) {
                removeExpired(cacheKey.storageKey, shard)
            }
            return null
        }
        shard.put(cacheKey.storageKey, entry)
        return response
    }

    private suspend fun put(cacheKey: DnsCacheKey, response: ByteArray): Boolean {
        val metadata = DnsMessageUtils.extractResponseTtlMetadata(response) ?: return false
        val upstreamTtl = metadata.minTtlSeconds
        val currentPolicy = policy
        val effectiveTtl = currentPolicy.effectiveTtlSeconds(upstreamTtl)
        if (effectiveTtl <= 0L) return false

        val now = System.currentTimeMillis()
        val entity = DnsCacheEntity(
            key = cacheKey.storageKey,
            queryName = cacheKey.name,
            queryType = cacheKey.type,
            queryClass = cacheKey.qclass,
            createdAt = now,
            expiresAt = now + effectiveTtl * 1000L,
            lastHitAt = null,
            hitCount = 0,
            originalTtlSeconds = upstreamTtl,
            ttlOffsets = metadata.ttlOffsets.joinToString(","),
            response = response.copyOf(),
            responseSize = response.size
        )
        val entry = DnsCacheEntry(
            entity = entity,
            ttlOffsets = metadata.ttlOffsets,
            staleExpiresAt = staleExpiresAt(entity.expiresAt, currentPolicy)
        )
        shardFor(cacheKey.storageKey).put(cacheKey.storageKey, entry)
        enqueueWrite(entity)
        return true
    }

    private suspend fun enqueueWrite(entity: DnsCacheEntity) {
        var flushNow = false
        pendingWriteMutex.withLock {
            pendingWrites[entity.key] = entity
            flushNow = pendingWrites.size >= WRITE_BATCH_SIZE
            if (flushNow) {
                pendingWriteFlushJob?.cancel()
                pendingWriteFlushJob = null
            } else if (pendingWriteFlushJob?.isActive != true) {
                pendingWriteFlushJob = scope.launch {
                    delay(WRITE_FLUSH_DELAY_MS)
                    flushPendingWrites()
                }
            }
        }
        if (flushNow) flushPendingWrites()
    }

    suspend fun flushPendingWrites() {
        val writes = pendingWriteMutex.withLock {
            pendingWriteFlushJob = null
            pendingWrites.values.toList().also { pendingWrites.clear() }
        }
        if (writes.isEmpty()) return
        runCatching { dao.insertAll(writes) }.onFailure {
            pendingWriteMutex.withLock {
                writes.forEach { entity -> pendingWrites.putIfAbsent(entity.key, entity) }
                if (pendingWriteFlushJob?.isActive != true) {
                    pendingWriteFlushJob = scope.launch {
                        delay(WRITE_FLUSH_DELAY_MS)
                        flushPendingWrites()
                    }
                }
            }
        }
    }

    private suspend fun clearPendingWrites() {
        pendingWriteMutex.withLock {
            pendingWriteFlushJob?.cancel()
            pendingWriteFlushJob = null
            pendingWrites.clear()
        }
    }

    private suspend fun materialize(
        entry: DnsCacheEntry,
        requestQuery: ByteArray,
        now: Long,
        allowStale: Boolean
    ): ByteArray? {
        val entity = entry.entity
        val expiresAt = entity.expiresAt
        val usable = if (allowStale) {
            now <= staleExpiresAt(expiresAt, policy)
        } else {
            now < expiresAt
        }
        if (!usable) return null

        val remainingSeconds = if (now < expiresAt) {
            ((expiresAt - now + 999L) / 1000L).coerceAtLeast(1L)
        } else {
            1L
        }
        val ttlPatched = DnsMessageUtils.patchResponseTtl(
            response = entity.response,
            ttlOffsets = entry.ttlOffsets,
            remainingTtlSeconds = remainingSeconds
        ) ?: return null
        if (!allowStale) {
            recordHit(entity.key, now)
        }
        return DnsMessageUtils.withTransactionId(ttlPatched, requestQuery)
    }

    private suspend fun recordHit(key: String, now: Long) {
        shardFor(key).recordHit(key, now)
        pendingHitMutex.withLock {
            val current = pendingHits[key]
            pendingHits[key] = if (current == null) {
                PendingHit(count = 1, lastHitAt = now)
            } else {
                current.copy(
                    count = current.count + 1,
                    lastHitAt = max(current.lastHitAt, now)
                )
            }
            if (pendingHitFlushJob?.isActive != true) {
                pendingHitFlushJob = scope.launch {
                    delay(HIT_FLUSH_DELAY_MS)
                    flushPendingHits()
                }
            }
        }
    }

    suspend fun flushPendingHits() {
        val hits = pendingHitMutex.withLock {
            pendingHitFlushJob = null
            if (pendingHits.isEmpty()) {
                emptyList()
            } else {
                pendingHits.map { (key, hit) ->
                    DnsCacheHitUpdate(
                        key = key,
                        count = hit.count,
                        lastHitAt = hit.lastHitAt
                    )
                }.also {
                    pendingHits.clear()
                }
            }
        }
        dao.recordHitsBatch(hits)
    }

    private suspend fun clearPendingHits() {
        pendingHitMutex.withLock {
            pendingHitFlushJob = null
            pendingHits.clear()
        }
    }

    private fun shouldDeleteUnavailable(entry: DnsCacheEntry, now: Long): Boolean {
        val currentPolicy = policy
        if (!currentPolicy.staleFallbackEnabled) return true
        return now > staleExpiresAt(entry.entity.expiresAt, currentPolicy)
    }

    private suspend fun removeExpired(key: String, shard: CacheShard) {
        shard.remove(key)
        dao.delete(key)
    }

    private fun shardFor(key: String): CacheShard {
        val index = (key.hashCode() and Int.MAX_VALUE) % shards.size
        return shards[index]
    }

    private fun DnsCacheEntity.toEntry(policy: DnsCachePolicy): DnsCacheEntry {
        return DnsCacheEntry(
            entity = this,
            ttlOffsets = ttlOffsets.split(',')
                .mapNotNull { it.toIntOrNull() }
                .toIntArray(),
            staleExpiresAt = staleExpiresAt(expiresAt, policy)
        )
    }

    private fun staleExpiresAt(expiresAt: Long, policy: DnsCachePolicy): Long {
        return if (policy.staleFallbackEnabled) {
            expiresAt + policy.staleFallbackSeconds.coerceAtLeast(0L) * 1000L
        } else {
            expiresAt
        }
    }

    private class CacheShard(private val maxSize: Int) {
        private val mutex = Mutex()
        private val memory = object : LinkedHashMap<String, DnsCacheEntry>(maxSize, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, DnsCacheEntry>?): Boolean {
                return size > maxSize
            }
        }

        suspend fun get(key: String): DnsCacheEntry? = mutex.withLock { memory[key] }

        suspend fun put(key: String, entry: DnsCacheEntry) {
            mutex.withLock { memory[key] = entry }
        }

        suspend fun remove(key: String) {
            mutex.withLock { memory.remove(key) }
        }

        suspend fun clear() {
            mutex.withLock { memory.clear() }
        }

        suspend fun recordHit(key: String, now: Long) {
            mutex.withLock {
                val current = memory[key] ?: return@withLock
                memory[key] = current.copy(
                    entity = current.entity.copy(
                        lastHitAt = now,
                        hitCount = current.entity.hitCount + 1
                    )
                )
            }
        }
    }

    companion object {
        private const val DEFAULT_MAX_ENTRIES = 2048
        private const val DEFAULT_SHARD_COUNT = 16
        private const val HIT_FLUSH_DELAY_MS = 2_000L
        private const val WRITE_FLUSH_DELAY_MS = 2_000L
        private const val WRITE_BATCH_SIZE = 32
    }
}

private data class PendingHit(
    val count: Int,
    val lastHitAt: Long
)
