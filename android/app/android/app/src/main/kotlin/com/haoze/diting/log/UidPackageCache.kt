package com.haoze.diting.log

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import java.net.InetAddress
import java.net.InetSocketAddress

/// Packet-origin UID -> package, two LRU levels; below API 29 resolveUid answers INVALID_UID.
///
/// The TTLs, the capacities and the LRU order live in the log kernel
/// (`rust/diting-log-core/src/attr.rs`); the `getConnectionOwnerUid` binder call and the
/// `PackageManager` lookup stay here, because only they can answer a miss.
class UidPackageCache(context: Context) {
    private val connectivityManager: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)
    private val packageManager: PackageManager = context.packageManager
    private val handle: Long = LogNative.attrNew()

    private val ownerUidSupported: Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /// UIDResolver payload: protocol is the IPPROTO number
    fun resolveUid(
        protocol: Long,
        localIP: String,
        localPort: Long,
        remoteIP: String,
        remotePort: Long,
    ): Int {
        // Android 9 (API < 29) has no `getConnectionOwnerUid`, so per-UID attribution — and with it
        // the per-app traffic and speed pipeline — is intentionally unsupported there. A product
        // decision keeps `minSdk = 28` and accepts "unavailable" rather than adding a
        // `NetworkStatsManager`/`/proc` fallback.
        if (!ownerUidSupported) return Process.INVALID_UID
        val cm = connectivityManager ?: return Process.INVALID_UID
        val key = flowKey(protocol, localIP, localPort, remoteIP, remotePort)
        LogNative.attrUidLookup(handle, key)?.let { return it }

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

        LogNative.attrUidStore(handle, key, uid)
        return uid
    }

    /// AppUidResolver payload. Empty means unknown; DnsLogWriter turns a blank value into NULL
    fun packageForUid(uid: Int): String = when (val cached = LogNative.attrPackageLookup(handle, uid)) {
        is LogPackageLookup.Hit -> cached.packageName
        LogPackageLookup.NotKnown -> ""
        LogPackageLookup.Miss -> {
            val resolved = runCatching {
                packageManager.getPackagesForUid(uid)?.firstOrNull()
            }.getOrNull().orEmpty()
            if (resolved.isNotEmpty()) LogNative.attrPackageStore(handle, uid, resolved)
            resolved
        }
    }

    fun clear() = LogNative.attrClear(handle)

    private fun flowKey(
        protocol: Long,
        localIP: String,
        localPort: Long,
        remoteIP: String,
        remotePort: Long,
    ): ByteArray = LogPayload.pack { out ->
        out.writeLong(protocol)
        LogPayload.writeString(out, localIP)
        out.writeLong(localPort)
        LogPayload.writeString(out, remoteIP)
        out.writeLong(remotePort)
    }
}
