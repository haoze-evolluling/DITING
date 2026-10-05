package com.haoze.diting.ui.settings

import android.content.Context
import android.content.SharedPreferences
import com.haoze.diting.data.RuleDataset
import org.json.JSONArray

internal const val PREFS_NAME = "dns_vpn_prefs"

internal fun datasetPrefs(context: Context, dataset: RuleDataset = RuleDataset.NORMAL): SharedPreferences {
    return context.getSharedPreferences(dataset.prefsName(), Context.MODE_PRIVATE)
}

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
