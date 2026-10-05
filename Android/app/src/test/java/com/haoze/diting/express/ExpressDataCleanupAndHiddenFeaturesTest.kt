package com.haoze.diting.express

import com.haoze.diting.express.ui.EXPRESS_SUPPORTED_FEATURES
import com.haoze.diting.express.ui.EXPRESS_SUPPORTED_FEATURE_KEYS
import com.haoze.diting.express.ui.ExpressCleanupAction
import com.haoze.diting.ui.localization.translateSettingsAndAppearanceExact
import com.haoze.diting.ui.settings.FeatureCategory
import com.haoze.diting.ui.settings.HiddenFeature
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpressDataCleanupAndHiddenFeaturesTest {

    @Test
    fun testExpressHiddenFeaturesOmitFullTunnelFeatures() {
        // Total features in HiddenFeature is 27
        assertEquals(27, HiddenFeature.entries.size)

        // Express supported features must be exactly 18
        assertEquals(18, EXPRESS_SUPPORTED_FEATURES.size)
        assertEquals(18, EXPRESS_SUPPORTED_FEATURE_KEYS.size)

        // 9 full-tunnel features must be omitted
        val omittedKeys = setOf(
            HiddenFeature.REWRITE_LIST.key,
            HiddenFeature.TRAFFIC_STATS.key,
            HiddenFeature.APP_RULES.key,
            HiddenFeature.BLOCKED_APPS.key,
            HiddenFeature.EXCLUDED_APPS.key,
            HiddenFeature.HTTPS_INSPECTION.key,
            HiddenFeature.OUTBOUND_PROXY.key,
            HiddenFeature.NETWORK_TOOLS.key,
            HiddenFeature.AGENT_API.key
        )

        for (omittedKey in omittedKeys) {
            assertFalse(
                "Feature $omittedKey should not be in EXPRESS_SUPPORTED_FEATURE_KEYS",
                EXPRESS_SUPPORTED_FEATURE_KEYS.contains(omittedKey)
            )
        }

        // Entire NETWORK_CONTROL category must be empty in Express Mode
        val networkControlFeatures = HiddenFeature.entries.filter {
            it.category == FeatureCategory.NETWORK_CONTROL && it in EXPRESS_SUPPORTED_FEATURES
        }
        assertTrue("NETWORK_CONTROL must have no items in Express mode", networkControlFeatures.isEmpty())

        // Entire ADVANCED_TOOLS category must be empty in Express Mode
        val advancedToolsFeatures = HiddenFeature.entries.filter {
            it.category == FeatureCategory.ADVANCED_TOOLS && it in EXPRESS_SUPPORTED_FEATURES
        }
        assertTrue("ADVANCED_TOOLS must have no items in Express mode", advancedToolsFeatures.isEmpty())

        // POLICIES_RULES category should only have RULE_CONTROL, BLACKLIST, WHITELIST
        val policyRulesFeatures = HiddenFeature.entries.filter {
            it.category == FeatureCategory.POLICIES_RULES && it in EXPRESS_SUPPORTED_FEATURES
        }
        assertEquals(3, policyRulesFeatures.size)
        assertFalse(policyRulesFeatures.contains(HiddenFeature.REWRITE_LIST))
    }

    @Test
    fun testExpressDataCleanupActionsOmitFullTunnelActions() {
        val actionNames = ExpressCleanupAction.entries.map { it.name }.toSet()

        // 5 full-tunnel cleanup actions must be physically omitted
        assertFalse("TRAFFIC must not be in ExpressCleanupAction", actionNames.contains("TRAFFIC"))
        assertFalse("ADDRESS_RULES must not be in ExpressCleanupAction", actionNames.contains("ADDRESS_RULES"))
        assertFalse("APP_RULES must not be in ExpressCleanupAction", actionNames.contains("APP_RULES"))
        assertFalse("OUTBOUND_PROXY must not be in ExpressCleanupAction", actionNames.contains("OUTBOUND_PROXY"))
        assertFalse("CA_CERTIFICATE must not be in ExpressCleanupAction", actionNames.contains("CA_CERTIFICATE"))

        // Must contain 11 applicable actions
        assertEquals(11, ExpressCleanupAction.entries.size)

        // Test that prompt texts are tailored for Express mode (no HTTP, no 覆写, no 证书)
        val logAction = ExpressCleanupAction.LOG
        assertFalse(logAction.message.contains("HTTP"))

        val domainRulesAction = ExpressCleanupAction.DOMAIN_RULES
        assertFalse(domainRulesAction.message.contains("覆写"))

        val allDataAction = ExpressCleanupAction.ALL_DATA
        assertFalse(allDataAction.message.contains("证书"))
        assertFalse(allDataAction.message.contains("流量统计"))
        assertFalse(allDataAction.message.contains("地址规则"))
    }

    @Test
    fun testExpressDataCleanupLocalizationAvailability() {
        for (action in ExpressCleanupAction.entries) {
            val titleTranslation = com.haoze.diting.ui.localization.LocalizationEngine.translateExact(action.title)
            assertNotNull("Title '${action.title}' should have translation", titleTranslation)

            val messageTranslation = com.haoze.diting.ui.localization.LocalizationEngine.translateExact(action.message)
            assertNotNull("Message '${action.message}' should have translation", messageTranslation)
        }
    }
}
