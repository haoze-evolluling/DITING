package com.haoze.dnssr

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.SystemClock
import com.haoze.dnssr.crash.CrashBreadcrumbs
import com.haoze.dnssr.crash.CrashCollector
import com.haoze.dnssr.crash.CrashHandler
import com.haoze.dnssr.crash.CrashLogManager

/**
 * Application entry point for DITING. Initializes app-wide infrastructure such
 * as crash capture and lifecycle tracking.
 */
class DnssrApp : Application() {

    private var startedActivityCount = 0

    companion object {
        @Volatile
        var instance: DnssrApp? = null
            private set
    }

    override fun onCreate() {
        super.onCreate()
        instance = this

        CrashCollector.appStartElapsedRealtime = SystemClock.elapsedRealtime()

        // Install the global uncaught-exception crash handler.
        CrashHandler.install(this)
        CrashBreadcrumbs.record("APP", "Application.onCreate() initialized")

        // Asynchronously check for and extract any uncaught native crash from the
        // previous run (Android 11+).
        Thread({
            CrashLogManager.checkAndCollectNativeCrashes(this)
        }, "NativeCrashCollector").start()

        // Track activity lifecycles to keep the foreground state current and to
        // record crash breadcrumbs.
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {
                CrashBreadcrumbs.record("LIFECYCLE", "${activity.javaClass.simpleName} created")
            }

            override fun onActivityStarted(activity: Activity) {
                startedActivityCount++
                if (startedActivityCount == 1) {
                    CrashHandler.isAppForeground = true
                    CrashBreadcrumbs.record("LIFECYCLE", "App entered foreground")
                }
            }

            override fun onActivityResumed(activity: Activity) {
                CrashHandler.currentActivityName = activity.javaClass.simpleName
                CrashBreadcrumbs.record("LIFECYCLE", "${activity.javaClass.simpleName} resumed")
            }

            override fun onActivityPaused(activity: Activity) {
                CrashBreadcrumbs.record("LIFECYCLE", "${activity.javaClass.simpleName} paused")
            }

            override fun onActivityStopped(activity: Activity) {
                startedActivityCount = maxOf(0, startedActivityCount - 1)
                if (startedActivityCount == 0) {
                    CrashHandler.isAppForeground = false
                    CrashBreadcrumbs.record("LIFECYCLE", "App entered background")
                }
            }

            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}

            override fun onActivityDestroyed(activity: Activity) {
                if (CrashHandler.currentActivityName == activity.javaClass.simpleName) {
                    CrashHandler.currentActivityName = null
                }
                CrashBreadcrumbs.record("LIFECYCLE", "${activity.javaClass.simpleName} destroyed")
            }
        })
    }
}
