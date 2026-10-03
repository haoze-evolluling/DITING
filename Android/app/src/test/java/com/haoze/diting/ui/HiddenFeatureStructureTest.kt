package com.haoze.diting.ui

import com.haoze.diting.ui.settings.FeatureCategory
import com.haoze.diting.ui.settings.HiddenFeature
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HiddenFeatureStructureTest {

    @Test
    fun `hidden feature keys are all unique and non-empty`() {
        val keys = HiddenFeature.entries.map { it.key }
        assertEquals(keys.distinct().size, keys.size)
        assertTrue(keys.all { it.isNotBlank() })
    }

    @Test
    fun `fromKey resolves every hidden feature`() {
        for (feature in HiddenFeature.entries) {
            val resolved = HiddenFeature.fromKey(feature.key)
            assertNotNull("Feature with key ${feature.key} should resolve", resolved)
            assertEquals(feature, resolved)
        }
    }

    @Test
    fun `feature counts match balanced category layout requirements`() {
        val dnsFeatures = HiddenFeature.entries.filter { it.category == FeatureCategory.DNS_SERVICES }
        val ruleFeatures = HiddenFeature.entries.filter { it.category == FeatureCategory.POLICIES_RULES }
        val netFeatures = HiddenFeature.entries.filter { it.category == FeatureCategory.NETWORK_CONTROL }
        val advFeatures = HiddenFeature.entries.filter { it.category == FeatureCategory.ADVANCED_TOOLS }
        val uiFeatures = HiddenFeature.entries.filter { it.category == FeatureCategory.INTERFACE_SETTINGS }
        val dataFeatures = HiddenFeature.entries.filter { it.category == FeatureCategory.DATA_MAINTENANCE }
        val aboutFeatures = HiddenFeature.entries.filter { it.category == FeatureCategory.ABOUT_APP }

        assertEquals(4, dnsFeatures.size)
        assertEquals(4, ruleFeatures.size)
        assertEquals(4, netFeatures.size)
        assertEquals(4, advFeatures.size)
        // Interface settings has 3 configurable features + 1 permanent portal ("隐藏功能") = 4 cards in Feature Hub
        assertEquals(3, uiFeatures.size)
        assertEquals(4, dataFeatures.size)
        assertEquals(4, aboutFeatures.size)

        assertEquals(27, HiddenFeature.entries.size)
    }
}
