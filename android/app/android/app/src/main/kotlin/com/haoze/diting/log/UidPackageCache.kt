package com.haoze.diting.log

import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Process
import java.net.InetAddress
import java.net.InetSocketAddress

class UidPackageCache(context: Context) {
    private val connectivityManager: ConnectivityManager? =
        context.getSystemService(ConnectivityManager::class.java)
    private val packageManager: PackageManager = context.packageManager

    private val ownerUidSupported: Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    fun resolveUid(
        protocol: Long,
        localAddress: ByteArray,
        localPort: Long,
        remoteAddress: ByteArray,
        remotePort: Long,
    ): Int {
        if (!ownerUidSupported) return Process.INVALID_UID
        val cm = connectivityManager ?: return Process.INVALID_UID

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

    fun packageForUid(uid: Int): String = runCatching {
        packageManager.getPackagesForUid(uid)?.firstOrNull()
    }.getOrNull().orEmpty()
}
