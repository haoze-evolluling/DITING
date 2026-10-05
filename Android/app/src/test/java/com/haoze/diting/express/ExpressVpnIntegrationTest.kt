package com.haoze.diting.express

import com.haoze.diting.express.notification.ExpressNotificationBuilder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ExpressVpnIntegrationTest {

    @Test
    fun testIntentActionConstants() {
        assertEquals("com.haoze.diting.express.START_VPN", ExpressVpnIntents.ACTION_START)
        assertEquals("com.haoze.diting.express.STOP_VPN", ExpressVpnIntents.ACTION_STOP)
        assertEquals("com.haoze.diting.express.REFRESH_CONFIG", ExpressVpnIntents.ACTION_REFRESH_CONFIG)
        assertEquals("com.haoze.diting.express.SYNC_RULES", ExpressVpnIntents.ACTION_SYNC_RULES)
        assertEquals("com.haoze.diting.express.CLEAR_CACHE", ExpressVpnIntents.ACTION_CLEAR_CACHE)
        assertEquals("com.haoze.diting.express.STATUS_CHANGED", ExpressVpnIntents.ACTION_STATUS_CHANGED)
        assertEquals("com.haoze.diting.express.REFRESH_FLOATING_LOG", ExpressVpnIntents.ACTION_REFRESH_FLOATING_LOG)
        assertEquals("com.haoze.diting.express.FLOATING_LOG_APP_STATE", ExpressVpnIntents.ACTION_FLOATING_LOG_APP_STATE)
    }

    @Test
    fun testTunnelManagerConstants() {
        assertEquals("10.0.0.2", ExpressTunnelManager.VPN_ADDRESS_V4)
        assertEquals("10.0.0.1", ExpressTunnelManager.DNS_SERVER_V4)
        assertEquals("fd00:abcd::2", ExpressTunnelManager.VPN_ADDRESS_V6)
        assertEquals("fd00:abcd::1", ExpressTunnelManager.DNS_SERVER_V6)
        assertEquals(1400, ExpressTunnelManager.VPN_MTU)
    }

    @Test
    fun testNotificationConstants() {
        assertEquals(2001, ExpressNotificationBuilder.NOTIFICATION_ID_EXPRESS_VPN)
        assertEquals("diting_express_vpn_channel", ExpressNotificationBuilder.CHANNEL_EXPRESS_VPN)
    }

    @Test
    fun testPublicDnsHijackListCoverage() {
        val ipv4List = com.haoze.diting.express.engine.PublicDnsHijackList.IPV4_HIJACK_IPS
        val ipv6List = com.haoze.diting.express.engine.PublicDnsHijackList.IPV6_HIJACK_IPS
        assertTrue(ipv4List.contains("8.8.8.8"))
        assertTrue(ipv4List.contains("1.1.1.1"))
        assertTrue(ipv4List.contains("223.5.5.5"))
        assertTrue(ipv6List.contains("2001:4860:4860::8888"))
        assertTrue(ipv6List.contains("2606:4700:4700::1111"))
    }
}
