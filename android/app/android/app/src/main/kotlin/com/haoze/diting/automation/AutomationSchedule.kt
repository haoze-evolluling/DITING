package com.haoze.diting.automation

import android.content.Context
import android.util.Log
import com.haoze.diting.core.rule.StorageContract
import com.haoze.diting.log.AppDatabase
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

/**
 * 计算所有已启用定时规则中最早的下一次触发时间。
 *
 * 调度语义：在窗口开始时刻触发；若当前已错过今天的窗口，则顺延到下一次窗口
 * （不补触发），避免条件不满足时反复重试。
 */
object AutomationSchedule {
    private const val TAG = "AutomationSchedule"
    private const val SEARCH_DAYS = 8

    data class NextDue(val available: Boolean, val atMs: Long?)

    fun nextDue(context: Context, now: Long): NextDue {
        val open = AppDatabase.open(context, StorageContract.GLOBAL)
        val db = (open as? AppDatabase.Open.Ready)?.db ?: return NextDue(false, null)
        var earliest: Long? = null
        val ok: Boolean = runCatching {
            db.query(
                "automation_rule",
                arrayOf("spec_json"),
                "enabled = 1",
                null,
                null,
                null,
                null,
            ).use { cursor ->
                while (cursor.moveToNext()) {
                    val raw: String = cursor.getString(0) ?: "{}"
                    val spec: JSONObject =
                        runCatching { JSONObject(raw) }.getOrNull() ?: continue
                    val trigger: JSONObject = spec.optJSONObject("trigger") ?: continue
                    if (trigger.optString("type") != AutomationSpecKeys.TRIGGER_SCHEDULE) continue
                    val window: JSONObject = trigger.optJSONObject("window") ?: JSONObject()
                    val start: Long = nextWindowStart(window, now) ?: continue
                    val current: Long? = earliest
                    if (current == null || start < current) earliest = start
                }
            }
        }.onFailure { Log.w(TAG, "计算定时规则失败", it) }.isSuccess
        if (!ok) return NextDue(false, null)
        return NextDue(true, earliest)
    }

    private fun nextWindowStart(window: JSONObject, now: Long): Long? {
        val startMin: Int = window.optInt("startMin", 0).coerceIn(0, 24 * 60 - 1)
        val days: Set<Int>? = window.optJSONArray("days")?.let(::isoDays)
        for (offset in 0..SEARCH_DAYS) {
            val candidate: Long = startAt(now, offset, startMin)
            if (candidate < now) continue
            if (days != null && isoDay(candidate) !in days) continue
            return candidate
        }
        return null
    }

    private fun isoDays(array: JSONArray): Set<Int>? {
        if (array.length() == 0) return null
        val days = HashSet<Int>()
        for (index in 0 until array.length()) {
            val day: Int = array.optInt(index, -1)
            if (day in 1..7) days.add(day)
        }
        return days.ifEmpty { null }
    }

    private fun startAt(now: Long, dayOffset: Int, startMin: Int): Long {
        val calendar = Calendar.getInstance()
        calendar.timeInMillis = now
        calendar.add(Calendar.DAY_OF_YEAR, dayOffset)
        calendar.set(Calendar.HOUR_OF_DAY, startMin / 60)
        calendar.set(Calendar.MINUTE, startMin % 60)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        return calendar.timeInMillis
    }

    private fun isoDay(atMs: Long): Int {
        val calendar = Calendar.getInstance()
        calendar.timeInMillis = atMs
        return ((calendar.get(Calendar.DAY_OF_WEEK) + 5) % 7) + 1
    }
}
