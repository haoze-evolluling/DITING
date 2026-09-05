package com.haoze.dnssr.crash

import android.content.Context
import android.util.Log
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.system.exitProcess

/**
 * 全局未捕获异常监听处理器。
 * 通过 Thread.setDefaultUncaughtExceptionHandler 注册，在崩溃时收集详尽诊断信息写入磁盘，
 * 并安全移交给系统原生异常处理器。
 */
class CrashHandler private constructor(
    private val appContext: Context,
    private val defaultHandler: Thread.UncaughtExceptionHandler?
) : Thread.UncaughtExceptionHandler {

    private val isHandling = AtomicBoolean(false)

    override fun uncaughtException(thread: Thread, throwable: Throwable) {
        if (!isHandling.compareAndSet(false, true)) {
            // 防止崩溃收集过程再次触发未捕获异常导致死循环
            defaultHandler?.uncaughtException(thread, throwable) ?: exitProcess(2)
            return
        }

        try {
            CrashBreadcrumbs.record(
                tag = "CRASH",
                message = "Uncaught exception in [${thread.name}]: ${throwable.javaClass.name}: ${throwable.message}",
                level = "FATAL"
            )

            val report = CrashCollector.collectReport(
                context = appContext,
                thread = thread,
                throwable = throwable,
                topActivityName = currentActivityName,
                isForeground = isAppForeground
            )

            val file = CrashLogManager.saveCrashReport(appContext, report)
            Log.e(TAG, "DNSSR Crash detected! Report saved to: ${file?.absolutePath}")

            // 记录连续崩溃事件并判断是否触发系统 Download 自动备份
            CrashLogManager.onCrashOccurred(appContext)
        } catch (e: Throwable) {
            Log.e(TAG, "Fatal error while capturing crash report", e)
        } finally {
            if (defaultHandler != null) {
                defaultHandler.uncaughtException(thread, throwable)
            } else {
                exitProcess(2)
            }
        }
    }

    companion object {
        private const val TAG = "CrashHandler"

        @Volatile
        var currentActivityName: String? = null

        @Volatile
        var isAppForeground: Boolean = false

        private var installed = false

        @Synchronized
        fun install(context: Context) {
            if (installed) return
            val appContext = context.applicationContext ?: context
            val defaultHandler = Thread.getDefaultUncaughtExceptionHandler()
            val handler = CrashHandler(appContext, defaultHandler)
            Thread.setDefaultUncaughtExceptionHandler(handler)
            installed = true
            Log.i(TAG, "Global UncaughtExceptionHandler installed successfully")
        }
    }
}
