package com.haoze.dnssr.vpn

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class DnsProviderTest {
    @Test
    fun supportsTraditionalDnsServerAddresses() {
        assertTrue(DnsProvider.isValidDnsHost("1.1.1.1"))
        assertTrue(DnsProvider.isValidDnsHost("dns.example.com"))
        assertFalse(DnsProvider.isValidDnsHost("not-a-host"))
    }

    @Test
    fun protocolListIncludesTraditionalDns() {
        assertTrue(DnsProtocol.DNS in DnsProtocol.MANAGED_PROTOCOLS)
    }

    @Test
    fun includesTraditionalDnsPresets() {
        val expectedHosts = mapOf(
            "preset_alidns_dns" to "223.5.5.5",
            "preset_dnspod_dns" to "119.29.29.29",
            "preset_360_dns" to "101.226.4.6",
            "preset_onedns_dns" to "117.50.10.10",
            "preset_cloudflare_dns" to "1.1.1.1",
            "preset_google_dns" to "8.8.8.8"
        )

        expectedHosts.forEach { (id, host) ->
            val provider = DnsProvider.PRESETS.single { it.id == id }
            assertTrue(provider.isPreset)
            assertEquals(DnsProtocol.DNS, provider.protocol)
            assertEquals(host, provider.host)
            assertEquals(DnsProvider.DEFAULT_DNS_PORT, provider.port)
        }
    }
}
