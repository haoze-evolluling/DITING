package com.haoze.diting.vpn

import androidx.work.Data
import com.haoze.diting.data.entity.SubscriptionEntity
import com.haoze.diting.data.entity.SubscriptionImportState
import com.haoze.diting.data.entity.SubscriptionKind
import com.haoze.diting.data.entity.SubscriptionSourceType
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.StringReader

class LocalSubscriptionOperationTest {

    @Test
    fun testLocalSubscriptionEntityCreation() {
        val subscription = SubscriptionEntity(
            url = "content://com.android.providers.media.documents/document/123",
            name = "My Custom Rules",
            sourceType = SubscriptionSourceType.LOCAL,
            kind = SubscriptionKind.DOMAIN,
            groupId = 5L,
            importState = SubscriptionImportState.IMPORTING
        )

        assertEquals("content://com.android.providers.media.documents/document/123", subscription.url)
        assertEquals("My Custom Rules", subscription.name)
        assertEquals(SubscriptionSourceType.LOCAL, subscription.sourceType)
        assertEquals(SubscriptionKind.DOMAIN, subscription.kind)
        assertEquals(5L, subscription.groupId)
        assertEquals(SubscriptionImportState.IMPORTING, subscription.importState)
        assertTrue(subscription.enabled)
    }

    @Test
    fun testAddLocalSubscriptionDataPackaging() {
        val input = Data.Builder()
            .putString(RuleOperationScheduler.KEY_TYPE, RuleOperationType.ADD_LOCAL_SUBSCRIPTION.name)
            .putString(RuleOperationScheduler.KEY_URI, "content://test/local_rules.txt")
            .putString(RuleOperationScheduler.KEY_NAME, "Local AdBlock")
            .putString(RuleOperationScheduler.KEY_KIND, SubscriptionKind.HOSTS)
            .putLong(RuleOperationScheduler.KEY_GROUP_ID, 101L)
            .build()

        assertEquals(RuleOperationType.ADD_LOCAL_SUBSCRIPTION.name, input.getString(RuleOperationScheduler.KEY_TYPE))
        assertEquals("content://test/local_rules.txt", input.getString(RuleOperationScheduler.KEY_URI))
        assertEquals("Local AdBlock", input.getString(RuleOperationScheduler.KEY_NAME))
        assertEquals(SubscriptionKind.HOSTS, input.getString(RuleOperationScheduler.KEY_KIND))
        assertEquals(101L, input.getLong(RuleOperationScheduler.KEY_GROUP_ID, -1))
        assertNull(input.getString(RuleOperationScheduler.KEY_URL))
    }

    @Test
    fun testLocalRuleTxtParsing() {
        val sampleTxt = """
            ! Title: Sample Local Rule File
            ||example.com^
            @@||allowed.example.com^
            127.0.0.1 fake.domain.test
        """.trimIndent()

        val badfilterKeys = AdGuardRuleParser.extractBadfilterKeys(StringReader(sampleTxt).buffered())
        val count = CategorizedRuleStreamImporter.countRules(StringReader(sampleTxt).buffered(), badfilterKeys)

        assertEquals(3, count)
    }
}
