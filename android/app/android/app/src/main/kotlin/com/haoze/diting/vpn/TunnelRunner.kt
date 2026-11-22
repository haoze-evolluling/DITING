package com.haoze.diting.vpn

import android.content.Context
import android.util.Log
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.SocketProtector
import com.haoze.diting.log.RuntimeEventLog

/** 全隧道会话线程：装载规则快照、启动引擎并监护会话，普通与简洁模式共用。 */
internal object TunnelRunner {
    private const val SESSION_POLL_MS = 200L

    fun start(
        context: Context,
        engine: Engine,
        dataset: RuleDataset,
        eventDomain: String,
        threadName: String,
        logTag: String,
        tunFd: Int,
        protect: (Int) -> Boolean,
        isStopping: () -> Boolean,
        onFatal: (String) -> Unit,
    ): Thread = Thread({
        try {
            try {
                EngineRuleLoader.apply(context, engine, dataset, logTag)
            } catch (t: Throwable) {
                Log.e(logTag, "Unable to build rule snapshot", t)
                RuntimeEventLog.error(
                    eventDomain,
                    "rule.snapshot_fail",
                    "error" to (t.message ?: t.javaClass.simpleName),
                )
                if (!isStopping()) {
                    onFatal("规则加载失败：${t.message ?: t.javaClass.simpleName}")
                    return@Thread
                }
            }
            engine.startFull(tunFd.toLong(), object : SocketProtector {
                override fun protect(fd: Long): Boolean = protect(fd.toInt())
            })
            while (!isStopping() && engine.isFullRunning()) {
                Thread.sleep(SESSION_POLL_MS)
            }
            Log.i(logTag, "tunnel exited")
        } catch (t: Throwable) {
            Log.e(logTag, "tunnel crashed", t)
            RuntimeEventLog.error(
                eventDomain,
                "tunnel.crashed",
                "error" to (t.message ?: t.javaClass.simpleName),
            )
            if (!isStopping()) {
                onFatal("隧道运行异常：${t.message ?: t.javaClass.simpleName}")
            }
        }
    }, threadName).also { it.start() }

    fun reload(
        context: Context,
        engine: Engine,
        dataset: RuleDataset,
        eventDomain: String,
        threadName: String,
        logTag: String,
    ): Thread = Thread({
        try {
            EngineRuleLoader.apply(context, engine, dataset, logTag)
            Log.i(logTag, "rule snapshot hot-reloaded")
        } catch (t: Throwable) {
            Log.e(logTag, "rule hot-reload failed; keeping previous rules", t)
            RuntimeEventLog.warn(
                eventDomain,
                "rule.reload_fail",
                "error" to (t.message ?: t.javaClass.simpleName),
            )
        }
    }, threadName).also { it.start() }
}
