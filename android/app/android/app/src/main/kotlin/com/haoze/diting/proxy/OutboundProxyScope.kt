package com.haoze.diting.proxy

import android.content.Context
import com.haoze.diting.log.PackageUids

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
