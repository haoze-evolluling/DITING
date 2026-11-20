package com.haoze.diting.normal

import android.util.Log
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.SocketProtector
import com.haoze.diting.log.RuntimeEventLog

internal object NormalTunnelRunner {
    private const val TAG = "DitingVpnService"

    private const val SESSION_POLL_MS = 200L

    fun start(
        service: DitingVpnService,
        engine: Engine,
        tunFd: Int,
        isStopping: () -> Boolean,
        onFatal: (String) -> Unit,
    ): Thread = Thread({
        try {
            try {
                EngineRuleLoader.apply(service, engine, RuleDataset.NORMAL, TAG)
            } catch (t: Throwable) {
                Log.e(TAG, "Unable to build rule snapshot", t)
                RuntimeEventLog.error("vpn", "rule.snapshot_fail", "error" to (t.message ?: t.javaClass.simpleName))
                if (!isStopping()) {
                    onFatal("规则加载失败：${t.message ?: t.javaClass.simpleName}")
                    return@Thread
                }
            }
            engine.startFull(tunFd.toLong(), object : SocketProtector {
                override fun protect(fd: Long): Boolean = service.protect(fd.toInt())
            })
            while (!isStopping() && engine.isFullRunning()) {
                Thread.sleep(SESSION_POLL_MS)
            }
            Log.i(TAG, "tunnel exited")
        } catch (t: Throwable) {
            Log.e(TAG, "tunnel crashed", t)
            RuntimeEventLog.error("vpn", "tunnel.crashed", "error" to (t.message ?: t.javaClass.simpleName))
            if (!isStopping()) {
                onFatal("隧道运行异常：${t.message ?: t.javaClass.simpleName}")
            }
        }
    }, "diting-tunnel").also { it.start() }

    fun reload(service: DitingVpnService, engine: Engine): Thread = Thread({
        try {
            EngineRuleLoader.apply(service, engine, RuleDataset.NORMAL, TAG)
            Log.i(TAG, "rule snapshot hot-reloaded")
        } catch (t: Throwable) {
            Log.e(TAG, "rule hot-reload failed; keeping previous rules", t)
            RuntimeEventLog.warn("vpn", "rule.reload_fail", "error" to (t.message ?: t.javaClass.simpleName))
        }
    }, "diting-rule-reload").also { it.start() }
}
