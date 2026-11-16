package com.haoze.diting.express

import com.haoze.diting.control.BlockPauseLink
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.OutboundProxyStatusCallback
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.EngineLogCallbacks
import com.haoze.diting.log.RequestStats
import com.haoze.diting.proxy.OutboundProxyBridge
import com.haoze.diting.proxy.OutboundProxyScope
import com.haoze.diting.vpn.VpnPlanNative

/// Engine-side configuration of the express tunnel, split out of the service: outbound proxy, DNS
/// config, log callbacks, filters and the resolver-only data plane. Throws on fatal config errors;
/// the service owns error reporting, failure cleanup and the tunnel thread.
internal object ExpressEngineConfig {
    fun configure(
        service: ExpressVpnService,
        engine: Engine,
        dnsConfig: String,
        proxyJson: String,
        ipv6Enabled: Boolean,
        logMode: String,
    ): EngineDataPlane {
        val proxyError = engine.configureOutboundProxy(
            OutboundProxyScope.resolve(service, proxyJson.ifBlank { VpnPlanNative.startDefaults.outboundProxy })
        )
        if (proxyError.isNotBlank()) {
            // Persisted before failing so the page shows the reason, as the legacy app did.
            OutboundProxyBridge.publishStatus(service, "error", proxyError)
        }
        require(proxyError.isBlank()) { proxyError }
        // Emits `connecting` inside startFull; without this callback nothing ever writes the
        // final ready/error state back to `dns_vpn_prefs`.
        engine.setOutboundProxyStatusCallback(object : OutboundProxyStatusCallback {
            override fun onOutboundProxyStatus(state: String, message: String) {
                OutboundProxyBridge.publishStatus(service, state, message)
            }
        })
        engine.applyDNSConfig(dnsConfig)
        RequestStats.reset()
        val logDatabase = RuleDataset.EXPRESS.logsDatabase()
        EngineLogCallbacks.attach(engine, service, logDatabase, logMode)
        engine.setFilterDNS(true)
        // Same rule as the full tunnel: no IPv6 in the narrow TUN means no AAAA answers, so a
        // client whose physical IPv6 is broken does not wait on a doomed IPv6 attempt.
        engine.setBlockIpv6(!ipv6Enabled)
        // R4: replay the persisted pause / allowlist-only onto this freshly started engine.
        BlockPauseLink.apply(service)

        // Resolvers only: no user traffic crosses the narrow TUN and there is no MITM stage.
        // The log tables live in the express database, so bootstrap rows and the cache mirror
        // must target it too.
        val plane = EngineDataPlane(service, logMode, logDatabase)
        try {
            plane.attachResolvers(engine)
            plane.attachBootstrap(engine)
            plane.attachCacheMirror(engine)
        } catch (t: Throwable) {
            // The service only receives the plane on success, so release it here instead of
            // relying on its failure path to find it.
            runCatching { plane.close() }
            throw t
        }
        return plane
    }
}
