package com.haoze.diting.core.rule

import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemStatus
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SubscriptionAutoUpdateEngineTest {

    private class FakeSubscriptionAutoUpdateDao : SubscriptionAutoUpdateDao {
        val items = mutableListOf<SubscriptionAutoUpdateItemEntity>()

        override suspend fun upsert(item: SubscriptionAutoUpdateItemEntity) {
            items.removeAll { it.batchId == item.batchId && it.subscriptionId == item.subscriptionId }
            items.add(item)
        }

        override suspend fun byStatus(batchId: String, status: String): List<SubscriptionAutoUpdateItemEntity> =
            items.filter { it.batchId == batchId && it.status == status }

        override suspend fun byBatch(batchId: String): List<SubscriptionAutoUpdateItemEntity> =
            items.filter { it.batchId == batchId }

        override suspend fun deleteBatch(batchId: String) {
            items.removeAll { it.batchId == batchId }
        }

        override suspend fun deleteItem(batchId: String, subscriptionId: Long) {
            items.removeAll { it.batchId == batchId && it.subscriptionId == subscriptionId }
        }

        override suspend fun clear() {
            items.clear()
        }

        override suspend fun deleteOrphans() {
            items.clear()
        }
    }

    @Test
    fun testRecordOutcomeUpdated() = runBlocking {
        val dao = FakeSubscriptionAutoUpdateDao()
        val batchId = "batch_test_1"
        val subscriptionId = 1001L
        val outcome = SubscriptionUpdateOutcome.Updated(ruleCount = 500)

        val changed = SubscriptionAutoUpdateEngine.recordOutcome(dao, batchId, subscriptionId, outcome)

        assertTrue(changed)
        val recorded = dao.items.find { it.batchId == batchId && it.subscriptionId == subscriptionId }
        assertEquals(SubscriptionAutoUpdateItemStatus.SUCCESS, recorded?.status)
        assertTrue(recorded?.changed == true)
        assertEquals(500, recorded?.ruleCount)
    }

    @Test
    fun testRecordOutcomeNotModified() = runBlocking {
        val dao = FakeSubscriptionAutoUpdateDao()
        val batchId = "batch_test_2"
        val subscriptionId = 1002L
        val outcome = SubscriptionUpdateOutcome.NotModified(ruleCount = 300)

        val changed = SubscriptionAutoUpdateEngine.recordOutcome(dao, batchId, subscriptionId, outcome)

        assertFalse(changed)
        val recorded = dao.items.find { it.batchId == batchId && it.subscriptionId == subscriptionId }
        assertEquals(SubscriptionAutoUpdateItemStatus.SUCCESS, recorded?.status)
        assertFalse(recorded?.changed == true)
        assertEquals(300, recorded?.ruleCount)
    }

    @Test
    fun testRecordOutcomeFailedRetryable() = runBlocking {
        val dao = FakeSubscriptionAutoUpdateDao()
        val batchId = "batch_test_3"
        val subscriptionId = 1003L
        val outcome = SubscriptionUpdateOutcome.Failed("Network timeout", retryable = true)

        val changed = SubscriptionAutoUpdateEngine.recordOutcome(dao, batchId, subscriptionId, outcome)

        assertFalse(changed)
        val recorded = dao.items.find { it.batchId == batchId && it.subscriptionId == subscriptionId }
        assertEquals(SubscriptionAutoUpdateItemStatus.PENDING_RETRY, recorded?.status)
    }

    @Test
    fun testRecordOutcomeFailedNonRetryable() = runBlocking {
        val dao = FakeSubscriptionAutoUpdateDao()
        val batchId = "batch_test_4"
        val subscriptionId = 1004L
        val outcome = SubscriptionUpdateOutcome.Failed("HTTP 404 Not Found", retryable = false)

        val changed = SubscriptionAutoUpdateEngine.recordOutcome(dao, batchId, subscriptionId, outcome)

        assertFalse(changed)
        val recorded = dao.items.find { it.batchId == batchId && it.subscriptionId == subscriptionId }
        assertEquals(SubscriptionAutoUpdateItemStatus.FAILED, recorded?.status)
    }

    @Test
    fun testCreateProgressData() {
        val data = SubscriptionAutoUpdateEngine.createProgressData(
            subscriptionId = 42L,
            current = 3,
            total = 10
        )
        assertEquals(RuleOperationType.UPDATE_SUBSCRIPTION.name, data.getString(RuleOperationScheduler.KEY_TYPE))
        assertEquals(42L, data.getLong(RuleOperationScheduler.KEY_SUBSCRIPTION_ID, -1))
        assertEquals(3, data.getInt(RuleOperationScheduler.KEY_CURRENT, -1))
        assertEquals(10, data.getInt(RuleOperationScheduler.KEY_TOTAL, -1))
    }
}
