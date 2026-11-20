package com.haoze.diting.log

internal object CrashTail {
    fun select(lines: List<String>, packageName: String): List<String> {
        if (lines.isEmpty()) return emptyList()
        return LogNative.crashSelect(packageName, lines)
    }
}
