package com.haoze.diting.automation

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.util.Log
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit

/// 定时控制器（A7）：把“下一次到期时间”同时挂到 AlarmManager 与 WorkManager 上。
///
/// 精确闹钟可用时用 setExactAndAllowWhileIdle；Android 12+ 未授予精确闹钟权限时退回
/// setAndAllowWhileIdle，绝不让缺少权限把整个定时链路断掉。WorkManager 的一次性任务是兜底，
/// 应对 Doze 或厂商杀后台导致闹钟被吞的情况。周期心跳任务则周期性补一次 tick。
object ScheduleController {
    private const val TAG = "ScheduleController"

    /// 一次性到期任务名与周期心跳任务名（enqueueUniqueWork 去重键）。
    private const val WORK_DUE = "diting-schedule-due"
    private const val WORK_HEARTBEAT = "diting-schedule-heartbeat"

    /// 闹钟 PendingIntent 的稳定 requestCode，保证同一时刻只有一个待触发闹钟。
    private const val ALARM_REQUEST_CODE = 4101

    /// WorkManager 周期任务的最小间隔是 15 分钟。
    private const val HEARTBEAT_INTERVAL_MINUTES = 15L

    /// 设定下一次到期时间：落盘 next_due_at，并同时安排闹钟与兜底任务。
    fun sync(context: Context, nextDueAtMs: Long) {
        val appContext: Context = context.applicationContext
        prefs(appContext).edit().putLong(AutomationContract.KEY_NEXT_DUE_AT_MS, nextDueAtMs).apply()
        val triggerAtMs: Long = maxOf(System.currentTimeMillis(), nextDueAtMs)
        scheduleAlarm(appContext, triggerAtMs)
        scheduleWork(appContext, nextDueAtMs)
    }

    /// 取消全部定时：撤销闹钟、撤销一次性兜底任务并清掉 next_due_at。
    fun cancel(context: Context) {
        val appContext: Context = context.applicationContext
        runCatching { alarmManager(appContext)?.cancel(alarmPendingIntent(appContext)) }
            .onFailure { Log.w(TAG, "取消定时闹钟失败", it) }
        runCatching { WorkManager.getInstance(appContext).cancelUniqueWork(WORK_DUE) }
            .onFailure { Log.w(TAG, "取消定时兜底任务失败", it) }
        prefs(appContext).edit().remove(AutomationContract.KEY_NEXT_DUE_AT_MS).apply()
    }

    /// 重启/校时/切时区后重建：仅当仍存有未来的 next_due_at 时重排。
    fun reschedule(context: Context) {
        val appContext: Context = context.applicationContext
        val nextDueAtMs: Long = prefs(appContext).getLong(AutomationContract.KEY_NEXT_DUE_AT_MS, 0L)
        if (nextDueAtMs > System.currentTimeMillis()) sync(appContext, nextDueAtMs)
    }

    /// 安装周期心跳任务；KEEP 语义保证重复调用不会重置已有的周期。
    fun install(context: Context) {
        val appContext: Context = context.applicationContext
        runCatching {
            val request: PeriodicWorkRequest = PeriodicWorkRequest.Builder(
                ScheduleWork::class.java,
                HEARTBEAT_INTERVAL_MINUTES,
                TimeUnit.MINUTES,
            ).build()
            WorkManager.getInstance(appContext)
                .enqueueUniquePeriodicWork(WORK_HEARTBEAT, ExistingPeriodicWorkPolicy.KEEP, request)
        }.onFailure { Log.w(TAG, "安装定时心跳任务失败", it) }
    }

    private fun scheduleAlarm(context: Context, triggerAtMs: Long) {
        val manager: AlarmManager = alarmManager(context) ?: return
        val pendingIntent: PendingIntent = alarmPendingIntent(context)
        runCatching {
            // Android 12+ 精确闹钟需要用户授权；没有授权就不能用精确接口。
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !manager.canScheduleExactAlarms()) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
            } else {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
            }
        }.onFailure { error ->
            Log.w(TAG, "精确闹钟不可用，退回非精确闹钟", error)
            runCatching {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
            }.onFailure { Log.w(TAG, "设置定时闹钟失败", it) }
        }
    }

    private fun scheduleWork(context: Context, nextDueAtMs: Long) {
        runCatching {
            val delayMs: Long = maxOf(0L, nextDueAtMs - System.currentTimeMillis())
            val request: OneTimeWorkRequest = OneTimeWorkRequest.Builder(ScheduleWork::class.java)
                .setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
                .build()
            WorkManager.getInstance(context)
                .enqueueUniqueWork(WORK_DUE, ExistingWorkPolicy.REPLACE, request)
        }.onFailure { Log.w(TAG, "安排定时兜底任务失败", it) }
    }

    private fun alarmManager(context: Context): AlarmManager? =
        context.getSystemService(AlarmManager::class.java)

    private fun alarmPendingIntent(context: Context): PendingIntent =
        PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            Intent(context, ScheduleAlarmReceiver::class.java)
                .setAction(AutomationContract.ACTION_SCHEDULE_TICK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(AutomationContract.PREFS_NAME, Context.MODE_PRIVATE)
}
