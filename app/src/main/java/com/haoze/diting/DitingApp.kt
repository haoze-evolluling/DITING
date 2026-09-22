package com.haoze.diting

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.SystemClock
import com.haoze.diting.crash.CrashBreadcrumbs
import com.haoze.diting.crash.CrashCollector
import com.haoze.diting.crash.CrashHandler
import com.haoze.diting.crash.CrashLogManager
import com.haoze.diting.vpn.RuleIndexLayout
import com.haoze.diting.vpn.SubscriptionAutoUpdateScheduler

/**
 * Application entry point for DITING. Initializes app-wide infrastructure such
 * as crash capture and lifecycle tracking.
 */
class DitingApp : Application() {

    private var startedActivityCount = 0

    companion object {
        @Volatile
        var instance: DitingApp? = null
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

        // Move rule index artifacts left over from the pre-type-split layout into
        // the current layout. Renames only, so an upgrade keeps its compiled
        // indexes; off the main thread because it touches the filesystem.
        Thread({
            runCatching { RuleIndexLayout.migrateLegacyLayout(filesDir) }
        }, "RuleIndexLayoutMigration").start()

        // Reconcile periodic rule subscription auto-update schedule on app startup.
        Thread({
            runCatching { SubscriptionAutoUpdateScheduler.sync(this) }
        }, "SubscriptionAutoUpdateSync").start()

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
