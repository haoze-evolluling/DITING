package com.haoze.diting.log

import android.content.Context

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
