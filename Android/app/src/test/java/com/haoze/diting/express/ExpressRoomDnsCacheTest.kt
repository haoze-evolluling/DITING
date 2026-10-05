package com.haoze.diting.express

import androidx.sqlite.db.SupportSQLiteQuery
import com.haoze.diting.data.dao.DnsCacheDao
import com.haoze.diting.data.entity.DnsCacheEntity
import com.haoze.diting.express.engine.ExpressDnsMessageUtils
import com.haoze.diting.vpn.cache.DnsCachePolicy
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.concurrent.ConcurrentHashMap

class ExpressRoomDnsCacheTest {

    private class FakeDnsCacheDao : DnsCacheDao {
        val storage = ConcurrentHashMap<String, DnsCacheEntity>()
        var hitCount = 0

        override suspend fun get(key: String): DnsCacheEntity? = storage[key]

        override suspend fun getUnexpired(now: Long, limit: Int): List<DnsCacheEntity> =
            storage.values.filter { it.expiresAt > now }.take(limit)

        override suspend fun countUnexpired(now: Long): Int =
            storage.values.count { it.expiresAt > now }

        override suspend fun totalHitCount(): Int = hitCount

        override suspend fun insert(entity: DnsCacheEntity) {
            storage[entity.key] = entity
        }

        override suspend fun insertAll(entities: List<DnsCacheEntity>) {
            entities.forEach { storage[it.key] = it }
        }

        override suspend fun recordHit(key: String, now: Long) {
            hitCount++
            storage[key]?.let {
                storage[key] = it.copy(hitCount = it.hitCount + 1, lastHitAt = now)
            }
        }

        override suspend fun delete(key: String) {
            storage.remove(key)
        }

        override suspend fun deleteExpired(now: Long): Int {
            val expired = storage.values.filter { it.expiresAt <= now }.map { it.key }
            expired.forEach { storage.remove(it) }
            return expired.size
        }

        override suspend fun clearAll() {
            storage.clear()
        }

        override suspend fun queryList(query: SupportSQLiteQuery): List<DnsCacheEntity> = emptyList()

        override suspend fun count(query: SupportSQLiteQuery): Int = storage.size
    }

    @Test
    fun testCachePutAndGetHit() = runBlocking {
        val fakeDao = FakeDnsCacheDao()
        val policy = DnsCachePolicy(enabled = true, minTtlSeconds = 60, maxTtlSeconds = 600)
        val cache = ExpressTunnelManager.ExpressRoomDnsCache(fakeDao) { policy }

        val query = ExpressDnsMessageUtils.buildQuery("example.com", ExpressDnsMessageUtils.TYPE_A)
        val question = ExpressDnsMessageUtils.extractQuestion(query)!!
        val answer = ExpressDnsMessageUtils.buildZeroAddressResponse(query)

        cache.put(question, answer)
        assertEquals(1, fakeDao.storage.size)

        val cachedResponse = cache.get(question, query)
        assertNotNull(cachedResponse)
        assertEquals(ExpressDnsMessageUtils.RCODE_NOERROR, ExpressDnsMessageUtils.responseCode(cachedResponse!!))
    }

    @Test
    fun testCacheDisabledPolicy() = runBlocking {
        val fakeDao = FakeDnsCacheDao()
        val disabledPolicy = DnsCachePolicy(enabled = false)
        val cache = ExpressTunnelManager.ExpressRoomDnsCache(fakeDao) { disabledPolicy }

        val query = ExpressDnsMessageUtils.buildQuery("example.com", ExpressDnsMessageUtils.TYPE_A)
        val question = ExpressDnsMessageUtils.extractQuestion(query)!!
        val answer = ExpressDnsMessageUtils.buildZeroAddressResponse(query)

        cache.put(question, answer)
        assertEquals(0, fakeDao.storage.size)

        val cachedResponse = cache.get(question, query)
        assertNull(cachedResponse)
    }

    @Test
    fun testCacheExpiredEntity() = runBlocking {
        val fakeDao = FakeDnsCacheDao()
        val policy = DnsCachePolicy(enabled = true)
        val cache = ExpressTunnelManager.ExpressRoomDnsCache(fakeDao) { policy }

        val query = ExpressDnsMessageUtils.buildQuery("expired.com", ExpressDnsMessageUtils.TYPE_A)
        val question = ExpressDnsMessageUtils.extractQuestion(query)!!

        val expiredEntity = DnsCacheEntity(
            key = "expired.com#1#1",
            queryName = "expired.com",
            queryType = 1,
            queryClass = 1,
            createdAt = System.currentTimeMillis() - 100_000L,
            expiresAt = System.currentTimeMillis() - 50_000L,
            lastHitAt = null,
            hitCount = 0,
            originalTtlSeconds = 50,
            ttlOffsets = "",
            response = ExpressDnsMessageUtils.buildZeroAddressResponse(query),
            responseSize = 32
        )
        fakeDao.insert(expiredEntity)

        val cachedResponse = cache.get(question, query)
        assertNull(cachedResponse)
        assertNull(fakeDao.get("expired.com#1#1"))
    }
}
