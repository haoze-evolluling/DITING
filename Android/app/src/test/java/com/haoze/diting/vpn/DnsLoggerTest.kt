package com.haoze.diting.vpn

import androidx.sqlite.db.SupportSQLiteQuery
import com.haoze.diting.data.dao.DailyStatRow
import com.haoze.diting.data.dao.DnsLogDao
import com.haoze.diting.data.dao.SubscriptionInterceptionStatRow
import com.haoze.diting.data.entity.DnsLogEntity
import com.haoze.diting.ui.DnsLogMode
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections

class DnsLoggerTest {

    private class FakeDnsLogDao : DnsLogDao {
        val inserted = Collections.synchronizedList(ArrayList<DnsLogEntity>())
        var cleared = false

        override suspend fun insert(entity: DnsLogEntity) {
            inserted.add(entity)
        }

        override suspend fun insertAll(entities: List<DnsLogEntity>) {
            inserted.addAll(entities)
        }

        override suspend fun deleteBefore(before: Long) {}

        override suspend fun clearAll() {
            cleared = true
            inserted.clear()
        }

        override suspend fun queryList(query: SupportSQLiteQuery): List<DnsLogEntity> = inserted.toList()
        override suspend fun count(query: SupportSQLiteQuery): Int = inserted.size
        override suspend fun dailyStats(since: Long): List<DailyStatRow> = emptyList()
        override suspend fun countSince(since: Long): Int = inserted.size
        override suspend fun subscriptionInterceptionStats(since: Long, blockedResult: String): List<SubscriptionInterceptionStatRow> = emptyList()
    }

    @Test
    fun testLogModeFiltering() {
        val fakeDao = FakeDnsLogDao()
        var mode = DnsLogMode.OFF
        val logger = DnsLogger(fakeDao) { mode }

        assertFalse(logger.isLoggable(LogResult.PASSED))
        assertFalse(logger.isLoggable(LogResult.BLOCKED))

        mode = DnsLogMode.BLOCKED_AND_ERRORS
        assertFalse(logger.isLoggable(LogResult.PASSED))
        assertTrue(logger.isLoggable(LogResult.BLOCKED))
        assertTrue(logger.isLoggable(LogResult.ERROR))

        mode = DnsLogMode.ALL
        assertTrue(logger.isLoggable(LogResult.PASSED))
        assertTrue(logger.isLoggable(LogResult.BLOCKED))
    }

    @Test
    fun testBatchFlushingWhenReachingBatchSize() = runBlocking {
        val fakeDao = FakeDnsLogDao()
        val logger = DnsLogger(fakeDao) { DnsLogMode.ALL }

        for (i in 1..49) {
            logger.log(
                queryName = "host$i.example.com",
                queryType = 1,
                result = LogResult.PASSED
            )
        }
        assertEquals(0, fakeDao.inserted.size)

        // 50th log triggers batch flush
        logger.log(
            queryName = "host50.example.com",
            queryType = 1,
            result = LogResult.BLOCKED
        )
        assertEquals(50, fakeDao.inserted.size)
        assertEquals("host50.example.com", fakeDao.inserted[49].queryName)
    }

    @Test
    fun testExplicitFlush() = runBlocking {
        val fakeDao = FakeDnsLogDao()
        val logger = DnsLogger(fakeDao) { DnsLogMode.ALL }

        logger.log("single.example.com", 1, LogResult.BLOCKED)
        assertEquals(0, fakeDao.inserted.size)

        logger.flush()
        assertEquals(1, fakeDao.inserted.size)
        assertEquals("single.example.com", fakeDao.inserted[0].queryName)
    }

    @Test
    fun testConcurrentBurstLogging() = runBlocking {
        val fakeDao = FakeDnsLogDao()
        val logger = DnsLogger(fakeDao, flushScope = this) { DnsLogMode.ALL }

        // Simulate 120 concurrent DNS queries arriving in game startup
        val jobs = (1..120).map { i ->
            async(Dispatchers.Default) {
                logger.log(
                    queryName = "qqfarm$i.game.qq.com",
                    queryType = 1,
                    result = if (i % 2 == 0) LogResult.BLOCKED else LogResult.PASSED
                )
            }
        }
        jobs.awaitAll()

        // Flush any remaining items in buffer (< BATCH_SIZE)
        logger.flush()

        assertEquals(120, fakeDao.inserted.size)
    }

    @Test
    fun testClearAll() = runBlocking {
        val fakeDao = FakeDnsLogDao()
        val logger = DnsLogger(fakeDao) { DnsLogMode.ALL }

        logger.log("test.com", 1, LogResult.PASSED)
        logger.clearAll()

        assertTrue(fakeDao.cleared)
        assertEquals(0, fakeDao.inserted.size)
    }
}
