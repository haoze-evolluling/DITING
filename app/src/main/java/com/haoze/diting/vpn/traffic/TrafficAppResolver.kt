package com.haoze.diting.vpn.traffic

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

/**
 * Handles package metadata resolution, caching, and background UID resolution for traffic statistics.
 */
internal class TrafficAppResolver {

    private val appInfoByUid = ConcurrentHashMap<Int, CachedAppInfo>()
    private val appInfoByPackage = ConcurrentHashMap<String, CachedAppInfo>()

    // Deduplication + negative cache for async package lookups on the snapshot path
    private val pendingPackageLookups = ConcurrentHashMap.newKeySet<String>()
    private val unresolvablePackages = ConcurrentHashMap.newKeySet<String>()

    fun getAppInfo(packageName: String): CachedAppInfo? = appInfoByPackage[packageName]

    fun getCachedAppInfoByUid(uid: Int): CachedAppInfo? = appInfoByUid[uid]

    fun getAllAppInfos(): Collection<CachedAppInfo> = appInfoByUid.values

    fun refreshAppList(context: Context) {
        try {
            val pm = context.packageManager
            val installed = pm.getInstalledApplications(0)
            val myPackage = context.packageName

            for (app in installed) {
                if (app.packageName == myPackage) continue
                val label = runCatching { app.loadLabel(pm).toString() }.getOrDefault(app.packageName)
                val isSys = SystemAppClassifier.isSystemApplicationInfo(app) ||
                    SystemAppClassifier.isKnownSystemPackagePrefix(app.packageName)
                val info = CachedAppInfo(app.uid, app.packageName, label, isSys)
                appInfoByUid[app.uid] = info
                appInfoByPackage[app.packageName] = info
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to refresh installed apps: ${e.message}")
        }
    }

    fun getOrResolveAppInfo(context: Context, uid: Int): CachedAppInfo? {
        val cached = appInfoByUid[uid]
        if (cached != null) return cached
        return try {
            val pm = context.packageManager
            val packages = pm.getPackagesForUid(uid)
            val pkg = packages?.firstOrNull()
            if (pkg != null) {
                val app = runCatching { pm.getApplicationInfo(pkg, 0) }.getOrNull()
                val label = app?.let { runCatching { it.loadLabel(pm).toString() }.getOrNull() } ?: pkg
                val isSys = app?.let { SystemAppClassifier.isSystemApplicationInfo(it) }
                    ?: (SystemAppClassifier.isKnownSystemPackagePrefix(pkg) || uid < 10000)
                val info = CachedAppInfo(uid, pkg, label, isSys)
                appInfoByUid[uid] = info
                appInfoByPackage[pkg] = info
                info
            } else if (uid < 10000) {
                val name = when (uid) {
                    0 -> "Root"
                    1000 -> "System"
                    1001 -> "Phone"
                    1013 -> "Media"
                    1020 -> "mDNS"
                    1073 -> "NetworkStack"
                    else -> "System ($uid)"
                }
                val info = CachedAppInfo(uid, "android.uid.system:$uid", name, true)
                appInfoByUid[uid] = info
                appInfoByPackage[info.packageName] = info
                info
            } else {
                null
            }
        } catch (_: Exception) {
            null
        }
    }

    fun schedulePackageLookup(
        context: Context,
        pkg: String,
        scope: CoroutineScope,
        onResolved: () -> Unit
    ) {
        if (pkg.startsWith("android.uid.system")) return
        if (unresolvablePackages.contains(pkg)) return
        if (!pendingPackageLookups.add(pkg)) return
        scope.launch(Dispatchers.IO) {
            try {
                val pm = context.packageManager
                val app = runCatching { pm.getApplicationInfo(pkg, 0) }.getOrNull()
                if (app != null) {
                    val label = runCatching { app.loadLabel(pm).toString() }.getOrDefault(pkg)
                    val isSys = SystemAppClassifier.isSystemApplicationInfo(app) ||
                        SystemAppClassifier.isKnownSystemPackagePrefix(pkg)
                    appInfoByPackage[pkg] = CachedAppInfo(app.uid, pkg, label, isSys)
                } else {
                    val isSys = SystemAppClassifier.isKnownSystemPackagePrefix(pkg)
                    if (isSys) {
                        appInfoByPackage[pkg] = CachedAppInfo(0, pkg, pkg, true)
                    } else {
                        // Cache the negative result for apps that cannot be
                        // resolved, avoiding a repeated lookup on every publish
                        unresolvablePackages.add(pkg)
                    }
                }
            } catch (e: Exception) {
                val isSys = SystemAppClassifier.isKnownSystemPackagePrefix(pkg)
                if (isSys) {
                    appInfoByPackage[pkg] = CachedAppInfo(0, pkg, pkg, true)
                } else {
                    unresolvablePackages.add(pkg)
                }
            } finally {
                pendingPackageLookups.remove(pkg)
            }
            onResolved()
        }
    }

    fun clear() {
        appInfoByUid.clear()
        appInfoByPackage.clear()
        pendingPackageLookups.clear()
        unresolvablePackages.clear()
    }

    companion object {
        private const val TAG = "TrafficAppResolver"
    }
}
