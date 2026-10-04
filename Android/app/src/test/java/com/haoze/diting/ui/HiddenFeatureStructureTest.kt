package com.haoze.diting.ui

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
}
