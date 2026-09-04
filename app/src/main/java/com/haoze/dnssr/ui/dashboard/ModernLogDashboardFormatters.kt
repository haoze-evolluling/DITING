package com.haoze.dnssr.ui.dashboard

import java.text.NumberFormat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

fun formatCount(value: Int): String {
    return NumberFormat.getIntegerInstance(Locale.CHINA).format(value)
}

fun formatClockTime(millis: Long): String {
    if (millis <= 0L) return "无"
    return SimpleDateFormat("HH:mm:ss", Locale.CHINA).format(Date(millis))
}
