package com.haoze.dnssr.ui.dashboard

import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt

fun formatCount(value: Int): String {
    return NumberFormat.getIntegerInstance(Locale.CHINA).format(value)
}

fun formatClockTime(millis: Long): String {
    if (millis <= 0L) return "无"
    return SimpleDateFormat("HH:mm:ss", Locale.CHINA).format(Date(millis))
}

fun formatPercent(value: Double): String {
    val rounded = (value * 1000.0).roundToInt() / 10.0
    return if (rounded % 1.0 == 0.0) {
        "${rounded.toInt()}%"
    } else {
        "$rounded%"
    }
}

fun formatMs(value: Double): String {
    return "${value.roundToInt()} ms"
}

fun formatDuration(seconds: Long): String {
    return when {
        seconds >= 3600L -> "${seconds / 3600L} 小时"
        seconds >= 60L -> "${seconds / 60L} 分钟"
        else -> "$seconds 秒"
    }
}

fun formatTrafficBytes(bytes: Long): String = when {
    bytes >= 1024L * 1024 * 1024 * 1024 -> String.format(Locale.US, "%.2f TB", bytes / (1024.0 * 1024 * 1024 * 1024))
    bytes >= 1024L * 1024 * 1024 -> String.format(Locale.US, "%.2f GB", bytes / (1024.0 * 1024 * 1024))
    bytes >= 1024L * 1024 -> String.format(Locale.US, "%.2f MB", bytes / (1024.0 * 1024))
    bytes >= 1024 -> String.format(Locale.US, "%.1f KB", bytes / 1024.0)
    else -> "$bytes B"
}

fun formatTrafficSpeed(bps: Long): String = when {
    bps >= 1024 * 1024 -> String.format(Locale.US, "%.2f MB/s", bps / (1024.0 * 1024.0))
    bps >= 1024 -> String.format(Locale.US, "%.0f KB/s", bps / 1024.0)
    else -> "$bps B/s"
}
