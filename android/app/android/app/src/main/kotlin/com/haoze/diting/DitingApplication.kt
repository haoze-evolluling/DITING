package com.haoze.diting

import android.app.Application
import android.util.Log
import com.haoze.diting.automation.ScheduleController
import com.haoze.diting.log.CrashLogWriter
import com.haoze.diting.log.RuntimeEventLog
import com.haoze.diting.platform.ServerModeRetirement
import com.haoze.diting.root.RootDnsService

/// The app's [Application]: installs the always-on runtime-event black box and a global uncaught
/// exception handler before any activity or Flutter engine exists.
///
/// Previously there was no `Application` subclass at all (`android:name="${applicationName}"`), so a
/// crash on a background thread produced nothing the troubleshooting page could show. This is the
/// one hook every uncaught Kotlin/Java failure passes through; the Dart side has its own
/// `PlatformDispatcher.onError` and both feed the same black box.
class DitingApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        RuntimeEventLog.install(this)
        RuntimeEventLog.info("app", "create")
        installUncaughtHandler()
        // Retired server-mode data is discarded, never migrated; run it before any UI or database
        // reader can observe the old stores.
        ServerModeRetirement.purge(this)
        // A process killed between rule install and teardown would otherwise leave every DNS
        // query redirected to a dead listener. The check is a plain pref read when nothing is
        // stale, so a normal launch never invokes su.
        RootDnsService.reconcileStaleRules(this)
        // 安装定时心跳任务；WorkManager 不可用时不能拖垮应用启动。
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
