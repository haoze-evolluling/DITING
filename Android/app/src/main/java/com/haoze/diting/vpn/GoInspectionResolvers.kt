package com.haoze.diting.vpn

import tunnel.AppUidResolver
import tunnel.UIDResolver

/**
 * Bridges Go-side network connection ownership and package lookup callbacks
 * with the Android-side [UidPackageCache].
 */
internal class CachedConnectionOwnerUidResolver(private val cache: UidPackageCache) : UIDResolver {
    override fun resolveUID(
        protocol: Long,
        localIP: String,
        localPort: Long,
        remoteIP: String,
        remotePort: Long
    ): Long {
        return cache.resolveUid(
            protocol.toInt(),
            localIP,
            localPort.toInt(),
            remoteIP,
            remotePort.toInt()
        ).toLong()
    }
}

internal class CachedAppPackageResolver(private val cache: UidPackageCache) : AppUidResolver {
    override fun packageForUid(uid: Long): String =
        cache.resolvePackageForUid(uid.toInt()).orEmpty()
}
