package com.haoze.dnssr.ui

import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider

internal val DEFAULT_HOME_VISIBLE_PROTOCOLS = DnsProtocol.MANAGED_PROTOCOLS.toSet()

data class HomeProviderVisibility(
    val visibleProtocols: Set<DnsProtocol> = DEFAULT_HOME_VISIBLE_PROTOCOLS,
    val hiddenProviderIds: Set<String> = emptySet(),
    val visibleProviderIds: Set<String> = emptySet()
) {
    fun isVisible(provider: DnsProvider): Boolean {
        return if (provider.protocol in visibleProtocols) {
            provider.id !in hiddenProviderIds
        } else {
            provider.id in visibleProviderIds
        }
    }

    fun isDefault(): Boolean {
        return visibleProtocols == DEFAULT_HOME_VISIBLE_PROTOCOLS &&
            hiddenProviderIds.isEmpty() && visibleProviderIds.isEmpty()
    }
}
