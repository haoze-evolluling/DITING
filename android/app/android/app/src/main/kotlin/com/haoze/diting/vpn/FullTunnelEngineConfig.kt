package com.haoze.diting.vpn

import android.content.Context
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
import java.io.File

/**
 * 普通模式与简洁模式共用的数据面配置。
 *
 * 普通模式启用全隧道能力——流量统计、HTTP 记录、分应用管控、HTTPS 检查；
 * 简洁模式 [dnsOnly] 只保留 DNS 过滤、日志、缓存与解析相关回调。
 */
internal object FullTunnelEngineConfig {
    private const val MITM_DIR = "go-mitm"

    fun configure(
        context: Context,
        dataset: RuleDataset,
        engine: Engine,
        args: TunnelStartArgs,
        blockIpv6: Boolean,
        preferIpv6: Boolean,
        logMode: String,
        httpsBypassRules: Set<String>,
        dnsOnly: Boolean,
        logTag: String,
    ): EngineDataPlane {
        if (!dnsOnly) {
            val proxyError = engine.configureOutboundProxy(
                OutboundProxyScope.resolve(
                    context,
                    args.proxyJson.ifBlank { VpnPlanNative.startDefaults.outboundProxy },
                ),
            )
            if (proxyError.isNotBlank()) {
                OutboundProxyBridge.publishStatus(context, "error", proxyError)
            }
            require(proxyError.isBlank()) { proxyError }
            engine.setOutboundProxyStatusCallback(object : OutboundProxyStatusCallback {
                override fun onOutboundProxyStatus(state: String, message: String) {
                    OutboundProxyBridge.publishStatus(context, state, message)
                }
            })
        }
        engine.applyDNSConfig(args.dnsConfig)
        RequestStats.reset()
        val logDatabase = dataset.logsDatabase()
        EngineLogCallbacks.attach(engine, context, logDatabase, logMode)
        engine.setFilterDNS(true)
        if (!dnsOnly) {
            engine.setBlockIpv6(blockIpv6)
            engine.setPreferIpv6(preferIpv6)
        }
        BlockPauseLink.applyTo(context, engine)

        val plane = EngineDataPlane(context, logMode, logDatabase)
        try {
            plane.attachResolvers(engine)
            plane.attachBootstrap(engine)
            plane.attachCacheMirror(engine)
            if (!dnsOnly) {
                plane.attachTraffic(engine)
                plane.attachHttp(engine)
                configurePerApp(
                    context = context,
                    engine = engine,
                    args = args,
                    httpsBypassRules = httpsBypassRules,
                    logTag = logTag,
                )
            }
        } catch (t: Throwable) {
            runCatching { plane.close() }
            throw t
        }
        return plane
    }

    private fun configurePerApp(
        context: Context,
        engine: Engine,
        args: TunnelStartArgs,
        httpsBypassRules: Set<String>,
        logTag: String,
    ) {
        val blockedUidCsv = PackageUids.csv(context, args.blockedPackages)
        if (blockedUidCsv.isNotEmpty()) {
            engine.setBlockedUIDs(blockedUidCsv)
        }

        if (args.inspectionEnabled) {
            val mitmDir = File(context.filesDir, MITM_DIR).apply { mkdirs() }
            val caPem = runCatching { engine.startStackMitm(mitmDir.absolutePath) }
                .getOrDefault("")
            if (caPem.isBlank()) {
                Log.w(logTag, "startStackMitm produced no CA; HTTPS inspection stays off")
            } else {
                engine.setMitmAllowedUIDs(PackageUids.csv(context, args.inspectionPackages))
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
