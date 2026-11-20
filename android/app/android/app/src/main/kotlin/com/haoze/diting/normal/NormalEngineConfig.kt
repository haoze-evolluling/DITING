package com.haoze.diting.normal

import android.util.Log
import com.haoze.diting.control.BlockPauseLink
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.OutboundProxyStatusCallback
import com.haoze.diting.log.EngineDataPlane
import com.haoze.diting.log.EngineLogCallbacks
import com.haoze.diting.log.PackageUids
import com.haoze.diting.log.RequestStats
import com.haoze.diting.proxy.OutboundProxyBridge
import com.haoze.diting.proxy.OutboundProxyScope
import com.haoze.diting.vpn.VpnPlanNative
import java.io.File

internal object NormalEngineConfig {
    private const val TAG = "DitingVpnService"

    private const val MITM_DIR = "go-mitm"

    fun configure(
        service: DitingVpnService,
        engine: Engine,
        dnsConfig: String,
        proxyJson: String,
        ipv6Enabled: Boolean,
        blockedPackages: Set<String>,
        inspectionPackages: Set<String>,
        inspectionEnabled: Boolean,
        logMode: String,
        httpsBypassRules: Set<String>,
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
        val logDatabase = RuleDataset.NORMAL.logsDatabase()
        EngineLogCallbacks.attach(engine, service, logDatabase, logMode)
        engine.setFilterDNS(true)
        engine.setBlockIpv6(!ipv6Enabled)
        BlockPauseLink.apply(service)

        val plane = EngineDataPlane(service, logMode, logDatabase)
        try {
            plane.attachResolvers(engine)
            plane.attachBootstrap(engine)
            plane.attachCacheMirror(engine)
            plane.attachTraffic(engine)
            plane.attachHttp(engine)
            configurePerApp(
                service = service,
                engine = engine,
                blockedPackages = blockedPackages,
                inspectionPackages = inspectionPackages,
                inspectionEnabled = inspectionEnabled,
                httpsBypassRules = httpsBypassRules,
            )
        } catch (t: Throwable) {
            runCatching { plane.close() }
            throw t
        }
        return plane
    }

    private fun configurePerApp(
        service: DitingVpnService,
        engine: Engine,
        blockedPackages: Set<String>,
        inspectionPackages: Set<String>,
        inspectionEnabled: Boolean,
        httpsBypassRules: Set<String>,
    ) {
        val blockedUidCsv = PackageUids.csv(service, blockedPackages)
        if (blockedUidCsv.isNotEmpty()) {
            engine.setBlockedUIDs(blockedUidCsv)
        }

        if (inspectionEnabled) {
            val mitmDir = File(service.filesDir, MITM_DIR).apply { mkdirs() }
            val caPem = runCatching { engine.startStackMitm(mitmDir.absolutePath) }
                .getOrDefault("")
            if (caPem.isBlank()) {
                Log.w(TAG, "startStackMitm produced no CA; HTTPS inspection stays off")
            } else {
                engine.setMitmAllowedUIDs(PackageUids.csv(service, inspectionPackages))
                if (httpsBypassRules.isNotEmpty()) {
                    engine.setHttpsBypassRules(httpsBypassRules.joinToString("\n"))
                }
                engine.setFilterHttp3(true)
            }
        } else {
            engine.setMitmAllowedUIDs("")
        }
    }
}
