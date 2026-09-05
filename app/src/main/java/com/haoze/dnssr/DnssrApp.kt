package com.haoze.dnssr

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.os.SystemClock
import com.haoze.dnssr.crash.CrashBreadcrumbs
import com.haoze.dnssr.crash.CrashCollector
import com.haoze.dnssr.crash.CrashHandler

/**
 * 谛听应用入口 Application，负责全局基础设施（如崩溃捕获与生命周期追踪）的初始化。
 */
class DnssrApp : Application() {

    private var startedActivityCount = 0

    override fun onCreate() {
        super.onCreate()

        CrashCollector.appStartTimeMillis = System.currentTimeMillis()
        CrashCollector.appStartElapsedRealtime = SystemClock.elapsedRealtime()

        // 注册全局异常崩溃捕获
        CrashHandler.install(this)
        CrashBreadcrumbs.record("APP", "Application.onCreate() initialized")

        // 监听并追踪 Activity 生命周期，更新运行状态与记录面包屑
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
