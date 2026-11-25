package com.haoze.diting

import android.app.Application
import android.util.Log
import com.haoze.diting.automation.AutomationNetworkObserver
import com.haoze.diting.automation.ScheduleController
import com.haoze.diting.log.CrashLogWriter
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.platform.ServerModeRetirement
import com.haoze.diting.root.RootDnsService

class DitingApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        RuntimeEventLog.install(this)
        RuntimeEventLog.info("app", "create")
        installUncaughtHandler()
        // WorkManager 与定时任务只属于主进程；:log 等辅助进程启动时尚未初始化
        // WorkManager，重复安装只会抛 IllegalStateException。
        if (!isMainProcess()) return
        ServerModeRetirement.purge(this)
        RootDnsService.reconcileStaleRules(this)
        runCatching { AutomationNetworkObserver.start(this) }
            .onFailure { Log.w(TAG, "启动网络自动化监听失败", it) }
        // WorkManager 初始化与任务安排会读数据库，放到后台线程，避免拖慢冷启动首帧。
        Thread({
            runCatching { ScheduleController.install(this) }
                .onFailure { Log.w(TAG, "安装定时心跳任务失败", it) }
            runCatching { ScheduleController.syncNext(this) }
                .onFailure { Log.w(TAG, "初始化定时任务失败", it) }
        }, "diting-schedule-init").apply { isDaemon = true }.start()
    }

    companion object {
        private const val TAG = "DitingApplication"
    }

    private fun isMainProcess(): Boolean = Application.getProcessName() == packageName

    private fun installUncaughtHandler() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            runCatching {
                RuntimeEventLog.fatal(
                    "crash",
                    "uncaught",
                    "thread" to thread.name,
                    "error" to error.toString(),
                )
            }
            runCatching { CrashLogWriter.write(this, thread, error) }
            if (previous != null) {
                previous.uncaughtException(thread, error)
            } else {
                android.os.Process.killProcess(android.os.Process.myPid())
                kotlin.system.exitProcess(10)
            }
        }
    }
}
