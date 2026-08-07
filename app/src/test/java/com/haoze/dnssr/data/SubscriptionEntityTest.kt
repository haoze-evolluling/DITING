package com.haoze.dnssr.data

import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionSourceType
import org.junit.Assert.assertEquals
import org.junit.Test

class SubscriptionEntityTest {

    @Test
    fun defaultsToRemoteSourceForExistingSubscriptionConstruction() {
        val subscription = SubscriptionEntity(url = "https://example.com/rules.txt", name = "Example")

        assertEquals(SubscriptionSourceType.REMOTE, subscription.sourceType)
    }

    @Test
    fun supportsLocalSourceForFileImportedSubscription() {
        val subscription = SubscriptionEntity(
            url = "content://documents/rules.txt",
            name = "rules.txt",
            sourceType = SubscriptionSourceType.LOCAL
        )

        assertEquals(SubscriptionSourceType.LOCAL, subscription.sourceType)
    }
}
