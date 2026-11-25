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

object ScheduleController {
    private const val TAG = "ScheduleController"

    private const val WORK_DUE = "diting-schedule-due"
    private const val WORK_HEARTBEAT = "diting-schedule-heartbeat"

    private const val ALARM_REQUEST_CODE = 4101

    private const val HEARTBEAT_INTERVAL_MINUTES = 15L

    @Synchronized
    fun sync(context: Context, nextDueAtMs: Long) {
        val appContext: Context = context.applicationContext
        prefs(appContext).edit().putLong(AutomationContract.KEY_NEXT_DUE_AT_MS, nextDueAtMs).apply()
        val triggerAtMs: Long = maxOf(System.currentTimeMillis(), nextDueAtMs)
        scheduleAlarm(appContext, triggerAtMs)
        scheduleWork(appContext, nextDueAtMs)
    }

    @Synchronized
    fun cancel(context: Context) {
        val appContext: Context = context.applicationContext
        runCatching { alarmManager(appContext)?.cancel(alarmPendingIntent(appContext)) }
            .onFailure { Log.w(TAG, "取消定时闹钟失败", it) }
        runCatching { WorkManager.getInstance(appContext).cancelUniqueWork(WORK_DUE) }
            .onFailure { Log.w(TAG, "取消定时兜底任务失败", it) }
        prefs(appContext).edit().remove(AutomationContract.KEY_NEXT_DUE_AT_MS).apply()
    }

    /** 按数据库中的规则重新计算并安排下一次定时。 */
    @Synchronized
    fun syncNext(context: Context) {
        val appContext: Context = context.applicationContext
        val now: Long = System.currentTimeMillis()
        val next: AutomationSchedule.NextDue = AutomationSchedule.nextDue(appContext, now)
        if (!next.available) return
        val atMs: Long? = next.atMs
        if (atMs == null) {
            cancel(appContext)
        } else {
            sync(appContext, maxOf(now, atMs))
        }
    }

    fun reschedule(context: Context) = syncNext(context)

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
            val useExact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                manager.canScheduleExactAlarms()
            if (useExact) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
            } else {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMs, pendingIntent)
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
