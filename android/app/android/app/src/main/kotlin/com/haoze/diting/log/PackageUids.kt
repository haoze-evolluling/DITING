package com.haoze.diting.log

import android.content.Context

/// Converts package lists into the UID CSV the engine expects, since the engine only
/// sees UIDs on the packet path. Uninstalled packages are dropped rather than mapped
/// to a sentinel: a removed package must not become UID 0 or 1000.
object PackageUids {
    fun csv(context: Context, packages: Collection<String>): String = packages
        .asSequence()
        .filter { it.isNotBlank() }
        .mapNotNull { packageName ->
            runCatching { context.packageManager.getPackageUid(packageName, 0) }.getOrNull()
        }
        .filter { it > 0 }
        .distinct()
        .joinToString(",")
}
