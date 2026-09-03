package com.haoze.dnssr.ui.traffic

import java.util.Locale

internal fun formatBytes(bytes: Long): String = when {
    bytes >= 1024L * 1024 * 1024 * 1024 -> String.format(Locale.US, "%.2f TB", bytes / (1024.0 * 1024 * 1024 * 1024))
    bytes >= 1024L * 1024 * 1024 -> String.format(Locale.US, "%.2f GB", bytes / (1024.0 * 1024 * 1024))
    bytes >= 1024L * 1024 -> String.format(Locale.US, "%.2f MB", bytes / (1024.0 * 1024))
    bytes >= 1024 -> String.format(Locale.US, "%.1f KB", bytes / 1024.0)
    else -> "$bytes B"
}

internal fun formatSpeed(bps: Long): String = when {
    bps >= 1024 * 1024 -> String.format(Locale.US, "%.2f MB/s", bps / (1024.0 * 1024.0))
    bps >= 1024 -> String.format(Locale.US, "%.0f KB/s", bps / 1024.0)
    else -> "$bps B/s"
}

internal fun formatDuration(ms: Long): String {
    val seconds = (ms / 1000) % 60
    val minutes = (ms / (1000 * 60)) % 60
    val hours = ms / (1000 * 60 * 60)
    return if (hours > 0) {
        String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
    } else {
        String.format(Locale.US, "%02d:%02d", minutes, seconds)
    }
}
