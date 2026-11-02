package com.haoze.diting.log

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import android.util.LruCache
import java.net.InetAddress
import java.net.InetSocketAddress

/// Packet-origin UID -> package, two LRU levels; below API 29 resolveUid answers INVALID_UID.
class UidPackageCache(context: Context) {
    private val connectivityManager: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)
    private val packageManager: PackageManager = context.packageManager

    private val flowUidCache = LruCache<StringFlowKey, CachedUid>(FLOW_CACHE_CAPACITY)
    private val uidPackageCache = LruCache<Int, String>(UID_PACKAGE_CACHE_CAPACITY)
    private val lock = Any()

    private val ownerUidSupported: Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    data class StringFlowKey(
        val protocol: Long,
        val localIP: String,
        val localPort: Long,
        val remoteIP: String,
        val remotePort: Long,
    )

    private data class CachedUid(val uid: Int, val timestamp: Long)

    /// UIDResolver payload: protocol is the IPPROTO number
    fun resolveUid(
        protocol: Long,
        localIP: String,
        localPort: Long,
        remoteIP: String,
        remotePort: Long,
    ): Int {
        if (!ownerUidSupported) return Process.INVALID_UID
        val cm = connectivityManager ?: return Process.INVALID_UID
        val key = StringFlowKey(protocol, localIP, localPort, remoteIP, remotePort)
        val now = System.currentTimeMillis()

        synchronized(lock) {
            flowUidCache.get(key)?.let { cached ->
                val ttl = if (isKnownUid(cached.uid)) {
                    FLOW_CACHE_TTL_MS
                } else {
                    FLOW_NEGATIVE_CACHE_TTL_MS
                }
                if (now - cached.timestamp < ttl) return cached.uid
            }
        }

        // The engine passes the app endpoint as localIP, matching getConnectionOwnerUid's `local`.
        val uid = runCatching {
            val app = InetAddress.getByName(localIP)
            val server = InetAddress.getByName(remoteIP)
            cm.getConnectionOwnerUid(
                protocol.toInt(),
                InetSocketAddress(app, localPort.toInt()),
                InetSocketAddress(server, remotePort.toInt()),
            )
        }.getOrDefault(Process.INVALID_UID)

        synchronized(lock) { flowUidCache.put(key, CachedUid(uid, now)) }
        return uid
    }

    /// AppUidResolver payload. Empty means unknown; DnsLogWriter turns a blank value into NULL
    fun packageForUid(uid: Int): String {
        if (!isKnownUid(uid)) return ""
        synchronized(lock) { uidPackageCache.get(uid)?.let { return it } }
        val resolved = runCatching {
            packageManager.getPackagesForUid(uid)?.firstOrNull()
        }.getOrNull().orEmpty()
        if (resolved.isNotEmpty()) {
            synchronized(lock) { uidPackageCache.put(uid, resolved) }
        }
        return resolved
    }

    fun clear() {
        synchronized(lock) {
            flowUidCache.evictAll()
            uidPackageCache.evictAll()
        }
    }

    private fun isKnownUid(uid: Int): Boolean = uid > 0 && uid != Process.INVALID_UID

    private companion object {
        const val FLOW_CACHE_CAPACITY = 1024
        const val UID_PACKAGE_CACHE_CAPACITY = 256
        const val FLOW_CACHE_TTL_MS = 10_000L
        const val FLOW_NEGATIVE_CACHE_TTL_MS = 2_000L
    }
}
