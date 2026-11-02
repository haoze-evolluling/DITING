package com.haoze.diting.proxy

import android.content.Context
import android.util.Log
import com.haoze.diting.log.PackageUids
import org.json.JSONArray
import org.json.JSONObject

/// Turns the `packages` list of a per-app outbound proxy config into the `uids` list the engine
/// matches on. Done at tunnel start, not in Dart, so a quick-settings restore after an app
/// reinstall still maps to the current UID.
object OutboundProxyScope {
    private const val TAG = "OutboundProxyScope"

    fun resolve(context: Context, proxyJson: String): String {
        if (proxyJson.isBlank()) return proxyJson
        return try {
            val json = JSONObject(proxyJson)
            val packages = json.optJSONArray("packages") ?: return proxyJson
            val names = (0 until packages.length()).map { packages.optString(it) }
            val uids = PackageUids.csv(context, names)
                .split(',')
                .mapNotNull { it.toIntOrNull() }
            json.remove("packages")
            json.put("uids", JSONArray(uids))
            json.toString()
        } catch (e: Exception) {
            // The engine reports a malformed config itself; pass it through unchanged.
            Log.w(TAG, "outbound proxy scope not resolved", e)
            proxyJson
        }
    }
}
