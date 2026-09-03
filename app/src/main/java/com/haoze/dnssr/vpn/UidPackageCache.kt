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
 * 运行时 DNS 数据包来源 UID 与包名解析及高效 LRU 缓存。
 *
 * 在 Android 10+ (API 29+) 通过 ConnectivityManager.getConnectionOwnerUid 提取发包进程 UID，
 * 并结合 PackageManager.getPackagesForUid 解析为应用包名。
 * 内置两级 LRU 缓存（5元组/端口 -> UID，UID -> 包名），将高频 DNS 查询下的解析开销降低至微秒级。
 */
class UidPackageCache(context: Context) {

    private val connectivityManager: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)
    private val packageManager: PackageManager = context.packageManager

    // 5元组缓存：防止短时间内同端口重试或连续发包重复 IPC 查询
    private val flowUidCache = LruCache<FlowKey, CachedUid>(FLOW_CACHE_CAPACITY)
    private val stringFlowUidCache = LruCache<StringFlowKey, CachedUid>(FLOW_CACHE_CAPACITY)

    // UID -> 包名缓存：进程生命周期内包名基本恒定
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
     * 根据 UDP/IP 5 元组解析发包应用包名。
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
     * 根据 UDP/IP 5 元组解析发包进程 UID。
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
     * 根据字符串形式的 IP 与端口 5 元组解析发包进程 UID。
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
     * 根据 UID 获取应用包名。
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
