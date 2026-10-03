package com.haoze.diting.vpn

import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemEntity
import com.haoze.diting.data.entity.SubscriptionAutoUpdateItemStatus
import com.haoze.diting.data.entity.SubscriptionEntity
import com.haoze.diting.data.entity.SubscriptionGroupEntity
import com.haoze.diting.data.entity.SubscriptionSourceType
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

    @Test
    fun testUngroupedAndGroupedSubscriptionFilterLogic() {
        val groupEnabled = SubscriptionGroupEntity(id = 1L, name = "Group Enabled", autoUpdateEnabled = true)
        val groupDisabled = SubscriptionGroupEntity(id = 2L, name = "Group Disabled", autoUpdateEnabled = false)
        val groups = mapOf(1L to groupEnabled, 2L to groupDisabled)

        val subUngrouped = SubscriptionEntity(
            id = 10L,
            url = "https://example.com/ungrouped.txt",
            name = "Ungrouped",
            sourceType = SubscriptionSourceType.REMOTE,
            enabled = true,
            groupId = null
        )
        val subInEnabledGroup = SubscriptionEntity(
            id = 11L,
            url = "https://example.com/enabled_group.txt",
            name = "In Enabled Group",
            sourceType = SubscriptionSourceType.REMOTE,
            enabled = true,
            groupId = 1L
        )
        val subInDisabledGroup = SubscriptionEntity(
            id = 12L,
            url = "https://example.com/disabled_group.txt",
            name = "In Disabled Group",
            sourceType = SubscriptionSourceType.REMOTE,
            enabled = true,
            groupId = 2L
        )
        val subDisabledRemote = SubscriptionEntity(
            id = 13L,
            url = "https://example.com/disabled.txt",
            name = "Disabled Remote",
            sourceType = SubscriptionSourceType.REMOTE,
            enabled = false,
            groupId = null
        )
        val subLocal = SubscriptionEntity(
            id = 14L,
            url = "local_file",
            name = "Local Subscription",
            sourceType = SubscriptionSourceType.LOCAL,
            enabled = true,
            groupId = null
        )

        val allSubs = listOf(subUngrouped, subInEnabledGroup, subInDisabledGroup, subDisabledRemote, subLocal)

        // Simulate SQL:
        // WHERE sub.sourceType = 'remote' AND sub.enabled = 1 AND (sub.groupId IS NULL OR grp.autoUpdateEnabled = 1)
        val filtered = allSubs.filter { sub ->
            sub.sourceType == SubscriptionSourceType.REMOTE &&
                sub.enabled &&
                (sub.groupId == null || groups[sub.groupId]?.autoUpdateEnabled == true)
        }

        assertEquals(2, filtered.size)
        assertTrue(filtered.any { it.id == 10L }) // Ungrouped is included
        assertTrue(filtered.any { it.id == 11L }) // In enabled group is included
        assertFalse(filtered.any { it.id == 12L }) // In disabled group is excluded
        assertFalse(filtered.any { it.id == 13L }) // Disabled subscription is excluded
        assertFalse(filtered.any { it.id == 14L }) // Local file is excluded
    }
}
