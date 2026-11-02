package com.haoze.diting.net

/// Malformed input passes through on purpose: the resolver rejects it, better than guessing a host.
internal object NetHost {

    fun sanitize(input: String): String {
        var value = input.trim()
        if (value.isEmpty()) return value
        val schemeIndex = value.indexOf("://")
        if (schemeIndex >= 0) value = value.substring(schemeIndex + 3)
        val cutIndex = value.indexOfAny(charArrayOf('/', '?', '#'))
        if (cutIndex >= 0) value = value.substring(0, cutIndex)
        val atIndex = value.lastIndexOf('@')
        if (atIndex >= 0) value = value.substring(atIndex + 1)
        if (value.startsWith("[")) {
            val endIndex = value.indexOf(']')
            if (endIndex > 0) value = value.substring(1, endIndex)
            return value
        }
        // Only one colon with a digit tail is a port; the `::` guard keeps `2001:db8::1` intact.
        if (!value.contains("::") && value.count { it == ':' } == 1) {
            val afterColon = value.substringAfter(':')
            if (afterColon.isNotEmpty() && afterColon.all { it.isDigit() }) {
                value = value.substringBefore(':')
            }
        }
        return value
    }
}
