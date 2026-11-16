package com.haoze.diting.normal

import android.util.Log
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.SocketProtector
import com.haoze.diting.log.RuntimeEventLog

/// Threads of the full tunnel: the run loop that builds the rule snapshot, starts the engine and
/// reports a self-terminated session, plus the in-place rule hot reload. Split out of the service
/// so the service stays focused on the Android lifecycle.
internal object NormalTunnelRunner {
    private const val TAG = "DitingVpnService"

    /// How often the tunnel thread checks whether the session it started is still running.
    private const val SESSION_POLL_MS = 200L

    /// Starts the tunnel worker and returns it. [onFatal] carries the user-facing failure text;
    /// it is only called while no stop is in flight.
    fun start(
        service: DitingVpnService,
        engine: Engine,
        tunFd: Int,
        isStopping: () -> Boolean,
        onFatal: (String) -> Unit,
    ): Thread = Thread({
        try {
            // Rules are built here, off the main thread: a stale index means a trie compile
            // that can take seconds, and onStartCommand would otherwise ANR the service.
            // Applied before startFull so the tunnel comes up with filtering already armed.
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
            // `startFull` returns once the session is up (the old Go method blocked until `stop`).
            // Polling keeps this thread the one place a self-terminated session is reported.
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

    /// Rebuilds the rule snapshot and re-applies it to the running engine so a newly imported or
    /// updated subscription takes effect without dropping the tunnel. A failure keeps the
    /// previous rules (the policy swap only happens once the new snapshot builds) instead of
    /// killing the VPN.
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
