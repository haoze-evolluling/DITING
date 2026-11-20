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
            OutboundProxyBridge.publishStatus(service, "error", proxyError)
        }
        require(proxyError.isBlank()) { proxyError }
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
        engine.setBlockIpv6(!ipv6Enabled)
        BlockPauseLink.apply(service)

        val plane = EngineDataPlane(service, logMode, logDatabase)
        try {
            plane.attachResolvers(engine)
            plane.attachBootstrap(engine)
            plane.attachCacheMirror(engine)
        } catch (t: Throwable) {
            runCatching { plane.close() }
            throw t
        }
        return plane
    }
}
