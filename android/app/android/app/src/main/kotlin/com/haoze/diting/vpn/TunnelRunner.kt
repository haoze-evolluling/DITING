package com.haoze.diting.vpn

import android.content.Context
import android.util.Log
import com.haoze.diting.core.rule.EngineRuleLoader
import com.haoze.diting.core.rule.RuleDataset
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.SocketProtector
import com.haoze.diting.log.RuntimeEventLog

/** TUN 会话线程：装载规则快照、启动引擎并监护会话，普通与简洁模式共用。 */
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
            // 规则装载可能较慢；期间用户已停止隧道时不要再把引擎拉起来。
            if (isStopping()) return@Thread
            engine.startFull(tunFd.toLong(), object : SocketProtector {
                override fun protect(fd: Long): Boolean = protect(fd.toInt())
            })
            awaitSession(engine, logTag, isStopping)
        } catch (t: Throwable) {
            crash(eventDomain, logTag, t, isStopping, onFatal)
        }
    }, threadName).also { it.start() }

    /**
     * 只为已经在运行的会话续挂监护线程。
     *
     * IPv6 策略热切换已由服务同步重建会话，这里不再装载规则或调用 startFull，
     * 只负责会话异常退出时的收尾。
     */
    fun guard(
        engine: Engine,
        eventDomain: String,
        threadName: String,
        logTag: String,
        isStopping: () -> Boolean,
        onFatal: (String) -> Unit,
    ): Thread = Thread({
        try {
            awaitSession(engine, logTag, isStopping)
        } catch (t: Throwable) {
            crash(eventDomain, logTag, t, isStopping, onFatal)
        }
    }, threadName).also { it.start() }

    fun reload(
        context: Context,
        engine: Engine,
        dataset: RuleDataset,
        eventDomain: String,
        threadName: String,
        logTag: String,
        isStopping: () -> Boolean,
    ): Thread = Thread({
        try {
            if (isStopping()) return@Thread
            EngineRuleLoader.apply(context, engine, dataset, logTag)
            if (isStopping()) return@Thread
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

    private fun awaitSession(engine: Engine, logTag: String, isStopping: () -> Boolean) {
        while (!isStopping() && engine.isFullRunning()) {
            Thread.sleep(SESSION_POLL_MS)
        }
        Log.i(logTag, "tunnel exited")
    }

    private fun crash(
        eventDomain: String,
        logTag: String,
        error: Throwable,
        isStopping: () -> Boolean,
        onFatal: (String) -> Unit,
    ) {
        Log.e(logTag, "tunnel crashed", error)
        RuntimeEventLog.error(
            eventDomain,
            "tunnel.crashed",
            "error" to (error.message ?: error.javaClass.simpleName),
        )
        if (!isStopping()) {
            onFatal("隧道运行异常：${error.message ?: error.javaClass.simpleName}")
        }
    }
}
