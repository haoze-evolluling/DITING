package com.haoze.diting

import android.app.Application
import com.haoze.diting.log.CrashLogWriter
import com.haoze.diting.log.RuntimeEventLog

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
