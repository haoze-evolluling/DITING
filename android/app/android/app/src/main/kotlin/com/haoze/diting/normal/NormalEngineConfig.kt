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

/// Engine-side configuration of the full tunnel, split out of the service: outbound proxy, DNS
/// config, log callbacks, filters, the data plane and the per-app firewall / MITM setup. Throws on
/// fatal config errors; the service owns error reporting, failure cleanup and the tunnel thread.
internal object NormalEngineConfig {
    private const val TAG = "DitingVpnService"

    /// Same directory the legacy app used: an upgraded install keeps its trusted root CA
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
            // Persisted before failing so the page shows the reason, as the legacy app did.
            OutboundProxyBridge.publishStatus(service, "error", proxyError)
        }
        require(proxyError.isBlank()) { proxyError }
        // Registered before startFull, which already emits `connecting`; without this the
        // engine's ready/error result never reaches `dns_vpn_prefs` and the page stays on
        // "正在连接" forever.
        engine.setOutboundProxyStatusCallback(object : OutboundProxyStatusCallback {
            override fun onOutboundProxyStatus(state: String, message: String) {
                OutboundProxyBridge.publishStatus(service, state, message)
            }
        })
        // Throws with the engine's rejection text.
        engine.applyDNSConfig(dnsConfig)
        // Counts belong to this run; the notification shows them since the tunnel came up.
        RequestStats.reset()
        val logDatabase = RuleDataset.NORMAL.logsDatabase(service)
        EngineLogCallbacks.attach(engine, service, logDatabase, logMode)
        engine.setFilterDNS(true)
        // The tunnel resolved `ipv6Mode` against the link (AUTO probe included). When it is
        // carrying no IPv6, answer AAAA with NODATA so traffic does not stall on IPv6.
        engine.setBlockIpv6(!ipv6Enabled)
        // R4: replay the persisted pause / allowlist-only onto this freshly started engine.
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
            // The service only receives the plane on success, so release it here instead of
            // relying on its failure path to find it.
            runCatching { plane.close() }
            throw t
        }
        return plane
    }

    /// Per-app firewall: the engine matches UIDs, not package names. Also arms HTTPS inspection
    /// for the selected apps.
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

        // Order matters: reversed, the UID list from setMitmAllowedUIDs is silently dropped.
        if (inspectionEnabled) {
            val mitmDir = File(service.filesDir, MITM_DIR).apply { mkdirs() }
            val caPem = runCatching { engine.startStackMitm(mitmDir.absolutePath) }
                .getOrDefault("")
            if (caPem.isBlank()) {
                // No CA means no filter, so startFull builds a plain passthrough stack.
                Log.w(TAG, "startStackMitm produced no CA; HTTPS inspection stays off")
            } else {
                engine.setMitmAllowedUIDs(PackageUids.csv(service, inspectionPackages))
                // The custom half of the bypass list is persisted by the inspection page as one
                // suffix per row. The old Go engine never received it (its setter had no caller),
                // so this is where the list finally reaches the filter.
                if (httpsBypassRules.isNotEmpty()) {
                    engine.setHttpsBypassRules(httpsBypassRules.joinToString("\n"))
                }
                // Drop QUIC for the inspected apps only, so HTTP/3 falls back to TCP and the
                // flows the user selected actually reach the MITM path.
                engine.setFilterHttp3(true)
            }
        } else {
            // Inspect nobody: the setter logs "stack MITM is not active" - expected.
            engine.setMitmAllowedUIDs("")
        }
    }
}
