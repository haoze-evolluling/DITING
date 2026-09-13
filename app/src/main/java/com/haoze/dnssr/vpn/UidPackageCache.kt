package com.haoze.dnssr.vpn

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Process
import android.system.OsConstants
import android.util.LruCache
import java.net.InetAddress
import java.net.InetSocketAddress

/**
 * Runtime resolution of DNS packet origin UIDs to package names, with an
 * efficient LRU cache.
 *
 * On Android 10+ (API 29+) the originating process UID is obtained via
 * ConnectivityManager.getConnectionOwnerUid, then mapped to an app package
 * name with PackageManager.getPackagesForUid. Two levels of LRU cache
 * (5-tuple/port -> UID, UID -> package name) reduce resolution overhead
 * under high-frequency DNS queries to the microsecond range.
 */
class UidPackageCache(context: Context) {

    private val connectivityManager: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)
    private val packageManager: PackageManager = context.packageManager

    // 5-tuple cache: prevents repeated IPC lookups for same-port retries or
    // bursts of packets within a short window
    private val flowUidCache = LruCache<FlowKey, CachedUid>(FLOW_CACHE_CAPACITY)
    private val stringFlowUidCache = LruCache<StringFlowKey, CachedUid>(FLOW_CACHE_CAPACITY)

    // UID -> package name cache: package names are essentially constant for the process lifetime
    private val uidPackageCache = LruCache<Int, String>(UID_PACKAGE_CACHE_CAPACITY)

    private val lock = Any()

    data class FlowKey(
        val protocol: Int,
        val sourceIp: InetAddress,
        val sourcePort: Int,
        val destIp: InetAddress,
        val destPort: Int
    )

    data class StringFlowKey(
        val protocol: Int,
        val localIP: String,
        val localPort: Int,
        val remoteIP: String,
        val remotePort: Int
    )

    private data class CachedUid(
        val uid: Int,
        val timestamp: Long
    )

    /**
     * Resolves the package name of the app that sent a UDP/IP packet from the 5-tuple.
     */
    fun resolvePackageName(
        sourceIp: InetAddress,
        sourcePort: Int,
        destIp: InetAddress,
        destPort: Int,
        protocol: Int = OsConstants.IPPROTO_UDP
    ): String? {
        val uid = resolveUid(sourceIp, sourcePort, destIp, destPort, protocol)
        if (uid <= 0 || uid == Process.INVALID_UID) return null
        return resolvePackageForUid(uid)
    }

    /**
     * Resolves the UID of the process that sent a UDP/IP packet from the 5-tuple.
     */
    fun resolveUid(
        sourceIp: InetAddress,
        sourcePort: Int,
        destIp: InetAddress,
        destPort: Int,
        protocol: Int = OsConstants.IPPROTO_UDP
    ): Int {
        val cm = connectivityManager ?: return Process.INVALID_UID

        val key = FlowKey(protocol, sourceIp, sourcePort, destIp, destPort)
        val now = System.currentTimeMillis()

        synchronized(lock) {
            flowUidCache.get(key)?.let { cached ->
                val ttl = if (cached.uid > 0 && cached.uid != Process.INVALID_UID) {
                    FLOW_CACHE_TTL_MS
                } else {
                    FLOW_NEGATIVE_CACHE_TTL_MS
                }
                if (now - cached.timestamp < ttl) {
                    return cached.uid
                }
            }
        }

        val uid = runCatching {
            cm.getConnectionOwnerUid(
                protocol,
                InetSocketAddress(sourceIp, sourcePort),
                InetSocketAddress(destIp, destPort)
            )
        }.getOrDefault(Process.INVALID_UID)

        synchronized(lock) {
            flowUidCache.put(key, CachedUid(uid, now))
        }

        return uid
    }

    /**
     * Resolves the UID of the sending process from a string-based IP/port 5-tuple.
     */
    fun resolveUid(
        protocol: Int,
        localIP: String,
        localPort: Int,
        remoteIP: String,
        remotePort: Int
    ): Int {
        val key = StringFlowKey(protocol, localIP, localPort, remoteIP, remotePort)
        val now = System.currentTimeMillis()

        synchronized(lock) {
            stringFlowUidCache.get(key)?.let { cached ->
                val ttl = if (cached.uid > 0 && cached.uid != Process.INVALID_UID) {
                    FLOW_CACHE_TTL_MS
                } else {
                    FLOW_NEGATIVE_CACHE_TTL_MS
                }
                if (now - cached.timestamp < ttl) {
                    return cached.uid
                }
            }
        }

        val src = runCatching { InetAddress.getByName(localIP) }.getOrNull() ?: return Process.INVALID_UID
        val dst = runCatching { InetAddress.getByName(remoteIP) }.getOrNull() ?: return Process.INVALID_UID
        val uid = resolveUid(src, localPort, dst, remotePort, protocol)

        synchronized(lock) {
            stringFlowUidCache.put(key, CachedUid(uid, now))
        }

        return uid
    }

    /**
     * Resolves an app package name from a UID.
     */
    fun resolvePackageForUid(uid: Int): String? {
        if (uid <= 0 || uid == Process.INVALID_UID) return null

        synchronized(lock) {
            uidPackageCache.get(uid)?.let { return it }
        }

        val packageName = runCatching {
            packageManager.getPackagesForUid(uid)?.firstOrNull()
        }.getOrNull()

        if (!packageName.isNullOrEmpty()) {
            synchronized(lock) {
                uidPackageCache.put(uid, packageName)
            }
        }

        return packageName
    }

    fun clear() {
        synchronized(lock) {
            flowUidCache.evictAll()
            stringFlowUidCache.evictAll()
            uidPackageCache.evictAll()
        }
    }

    companion object {
        private const val FLOW_CACHE_CAPACITY = 1024
        private const val UID_PACKAGE_CACHE_CAPACITY = 256
        private const val FLOW_CACHE_TTL_MS = 10_000L
        private const val FLOW_NEGATIVE_CACHE_TTL_MS = 2_000L
    }
}
