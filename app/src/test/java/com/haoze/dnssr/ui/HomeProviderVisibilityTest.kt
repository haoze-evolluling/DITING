package com.haoze.dnssr.ui

import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeProviderVisibilityTest {

    private val dnsProvider = DnsProvider(id = "dns", name = "DNS", protocol = DnsProtocol.DNS)
    private val dohProvider = DnsProvider(id = "doh", name = "DoH", protocol = DnsProtocol.DOH)

    @Test
    fun defaultVisibilityShowsEveryManagedProvider() {
        val visibility = HomeProviderVisibility()

        assertTrue(visibility.isVisible(dnsProvider))
        assertTrue(visibility.isVisible(dohProvider))
        assertTrue(visibility.isDefault())
    }

    @Test
    fun providerOverridesApplyWithinAndOutsideProtocolSelection() {
        val visibility = HomeProviderVisibility(
            visibleProtocols = setOf(DnsProtocol.DOH),
            hiddenProviderIds = setOf(dohProvider.id),
            visibleProviderIds = setOf(dnsProvider.id)
        )

        assertFalse(visibility.isVisible(dohProvider))
        assertTrue(visibility.isVisible(dnsProvider))
    }
}
