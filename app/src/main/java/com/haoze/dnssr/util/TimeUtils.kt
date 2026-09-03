package com.haoze.dnssr.util

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

const val SEVEN_DAYS_MILLIS = 7L * 24L * 60L * 60L * 1000L

fun dayStartMillis(): Long {
    val now = System.currentTimeMillis()
    val zoneOffset = TimeZone.getDefault().getOffset(now)
    return (now + zoneOffset) / 86_400_000L * 86_400_000L - zoneOffset
}

/** TODAY/SEVEN_DAYS/ALL 三档统计区间的起始时间戳（ALL 及未知档位返回 0）。 */
fun statsRangeStartMillis(range: Enum<*>): Long = when (range.name) {
    "TODAY" -> dayStartMillis()
    "SEVEN_DAYS" -> System.currentTimeMillis() - SEVEN_DAYS_MILLIS
    else -> 0L
}

/** 本地时区下 timestamp 所在日期的 yyyy-MM-dd 表示。 */
fun dayStringAt(timestamp: Long): String =
    SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date(timestamp))

fun currentDayString(): String = dayStringAt(System.currentTimeMillis())
