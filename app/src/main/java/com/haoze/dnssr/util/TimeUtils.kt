package com.haoze.dnssr.util

import java.util.TimeZone

fun dayStartMillis(): Long {
    val now = System.currentTimeMillis()
    val zoneOffset = TimeZone.getDefault().getOffset(now)
    return (now + zoneOffset) / 86_400_000L * 86_400_000L - zoneOffset
}
