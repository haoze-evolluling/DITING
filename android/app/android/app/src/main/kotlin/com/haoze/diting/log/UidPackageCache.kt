package com.haoze.diting.log

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import java.net.InetAddress
import java.net.InetSocketAddress

/// Packet-origin UID -> package, resolved on a miss only.
///
/// The engine already keeps the two TTL caches (2 s for a flow, 60 s for a package) in
/// `rust/diting-engine/src/attribution.rs`, and it only calls these two methods when its own lookup
/// misses. The old second-level cache in `diting-log-core/src/attr.rs` therefore never hit, while
/// every flow miss still packed a key, crossed JNI twice and stored the answer again; the binder
/// call and the `PackageManager` lookup are the only work that has to stay here, because only they
/// can answer a miss.
class UidPackageCache(context: Context) {
    private val connectivityManager: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)
    private val packageManager: PackageManager = context.packageManager

    private val ownerUidSupported: Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /// UIDResolver payload: protocol is the IPPROTO number and the two addresses are their raw
    /// wire bytes (4 for IPv4, 16 for IPv6), ready for `InetAddress.getByAddress`.
    fun resolveUid(
        protocol: Long,
        localAddress: ByteArray,
        localPort: Long,
        remoteAddress: ByteArray,
        remotePort: Long,
    ): Int {
        // Android 9 (API < 29) has no `getConnectionOwnerUid`, so per-UID attribution — and with it
        // the per-app traffic and speed pipeline — is intentionally unsupported there. A product
        // decision keeps `minSdk = 28` and accepts "unavailable" rather than adding a
        // `NetworkStatsManager`/`/proc` fallback.
        if (!ownerUidSupported) return Process.INVALID_UID
        val cm = connectivityManager ?: return Process.INVALID_UID

        // The engine passes the app endpoint as the local side, matching `getConnectionOwnerUid`.
        return runCatching {
            val app = InetAddress.getByAddress(localAddress)
            val server = InetAddress.getByAddress(remoteAddress)
            cm.getConnectionOwnerUid(
                protocol.toInt(),
                InetSocketAddress(app, localPort.toInt()),
                InetSocketAddress(server, remotePort.toInt()),
            )
        }.getOrDefault(Process.INVALID_UID)
    }

    /// AppUidResolver payload. Empty means unknown; DnsLogWriter turns a blank value into NULL.
    fun packageForUid(uid: Int): String = runCatching {
        packageManager.getPackagesForUid(uid)?.firstOrNull()
    }.getOrNull().orEmpty()
}
