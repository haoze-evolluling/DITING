package com.haoze.dnssr.ui.settings

import org.json.JSONArray

internal const val PREFS_NAME = "dns_vpn_prefs"

internal fun readStringSet(json: String?): Set<String>? {
    if (json == null) return null
    return try {
        val array = JSONArray(json)
        buildSet {
            for (index in 0 until array.length()) add(array.getString(index))
        }
    } catch (_: Exception) {
        null
    }
}

internal fun writeStringSet(values: Set<String>): String {
    return JSONArray().apply { values.sorted().forEach(::put) }.toString()
}
