package com.haoze.diting.proxy

import android.content.Context
import com.haoze.diting.log.PackageUids

/// Turns the `packages` list of a per-app outbound proxy config into the `uids` list the engine
/// matches on. Done at tunnel start, not in Dart, so a quick-settings restore after an app
/// reinstall still maps to the current UID.
///
/// The JSON rewrite and the package filtering table live in `rust/diting-outbound-proxy-core`;
/// only PackageManager (through [PackageUids]) stays here.
object OutboundProxyScope {
    fun resolve(context: Context, proxyJson: String): String {
        if (proxyJson.isBlank()) return proxyJson
        val packages = OutboundProxyNative.packagesOf(proxyJson) ?: return proxyJson
        val uids = PackageUids.csv(
            context,
            packages.split('\n').filter { it.isNotEmpty() },
        )
        return OutboundProxyNative.withUids(proxyJson, uids)
    }
}
