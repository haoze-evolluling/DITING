package com.haoze.diting.notification

import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.express.notification.ExpressNotificationBuilder
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class VpnNotificationIdConflictTest {

    @Test
    fun `notification IDs across modes and monitor are distinct and strictly partitioned`() {
        val monitorId = VpnMonitorService.NOTIFICATION_ID_VPN_MONITOR
        val legacyVpnId = VpnNotificationBuilder.NOTIFICATION_ID_VPN_SERVICE
        val expressVpnId = ExpressNotificationBuilder.NOTIFICATION_ID_EXPRESS_VPN

        assertEquals(1002, monitorId)
        assertEquals(1001, legacyVpnId)
        assertEquals(2001, expressVpnId)

        assertNotEquals(monitorId, legacyVpnId)
        assertNotEquals(monitorId, expressVpnId)
        assertNotEquals(legacyVpnId, expressVpnId)
    }

    @Test
    fun `notification channels across services are separated`() {
        assertEquals("diting_vpn_monitor_channel", AppNotificationChannels.CHANNEL_VPN_MONITOR)
        assertEquals("diting_express_vpn_channel", ExpressNotificationBuilder.CHANNEL_EXPRESS_VPN)
        assertEquals("diting_vpn_service_channel", AppNotificationChannels.CHANNEL_VPN_SERVICE)

        assertNotEquals(AppNotificationChannels.CHANNEL_VPN_MONITOR, ExpressNotificationBuilder.CHANNEL_EXPRESS_VPN)
        assertNotEquals(AppNotificationChannels.CHANNEL_VPN_SERVICE, ExpressNotificationBuilder.CHANNEL_EXPRESS_VPN)
    }

    @Test
    fun `express VPN service liveness flag reflects state accurately`() {
        val original = ExpressVpnService.isServiceAlive
        try {
            ExpressVpnService.isServiceAlive = false
            assertFalse(ExpressVpnService.isServiceAlive)

            ExpressVpnService.isServiceAlive = true
            assertTrue(ExpressVpnService.isServiceAlive)
        } finally {
            ExpressVpnService.isServiceAlive = original
        }
    }
}
