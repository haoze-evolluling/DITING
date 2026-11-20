package com.haoze.diting

import android.app.Application
import android.util.Log
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
        ServerModeRetirement.purge(this)
        RootDnsService.reconcileStaleRules(this)
        runCatching { ScheduleController.install(this) }
            .onFailure { Log.w(TAG, "安装定时心跳任务失败", it) }
    }

    companion object {
        private const val TAG = "DitingApplication"
    }

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
