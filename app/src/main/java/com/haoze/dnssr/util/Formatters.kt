package com.haoze.dnssr.util

import java.util.Locale
import kotlin.math.roundToInt

fun formatBytes(bytes: Long): String = when {
    bytes >= 1024L * 1024 * 1024 * 1024 -> String.format(Locale.US, "%.2f TB", bytes / (1024.0 * 1024 * 1024 * 1024))
    bytes >= 1024L * 1024 * 1024 -> String.format(Locale.US, "%.2f GB", bytes / (1024.0 * 1024 * 1024))
    bytes >= 1024L * 1024 -> String.format(Locale.US, "%.2f MB", bytes / (1024.0 * 1024))
    bytes >= 1024 -> String.format(Locale.US, "%.1f KB", bytes / 1024.0)
    else -> "$bytes B"
}

fun formatSpeed(bps: Long): String = when {
    bps >= 1024 * 1024 -> String.format(Locale.US, "%.2f MB/s", bps / (1024.0 * 1024.0))
    bps >= 1024 -> String.format(Locale.US, "%.0f KB/s", bps / 1024.0)
    else -> "$bps B/s"
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

/** Input is seconds; outputs a coarse duration with hardcoded Chinese unit characters (hours/minutes/seconds) rather than localized strings. */
fun formatDuration(seconds: Long): String {
    return when {
        seconds >= 3600L -> "${seconds / 3600L} 小时"
        seconds >= 60L -> "${seconds / 60L} 分钟"
        else -> "$seconds 秒"
    }
}

/** Input is milliseconds; outputs a stopwatch-style "HH:MM:SS" duration ("MM:SS" under one hour). */
fun formatDurationClock(ms: Long): String {
    val seconds = (ms / 1000) % 60
    val minutes = (ms / (1000 * 60)) % 60
    val hours = ms / (1000 * 60 * 60)
    return if (hours > 0) {
        String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.US, "%02d:%02d", minutes, seconds)
    }
}
