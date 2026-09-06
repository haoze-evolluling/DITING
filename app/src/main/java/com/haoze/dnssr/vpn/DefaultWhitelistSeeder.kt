package com.haoze.dnssr.vpn

import android.content.Context
import android.util.Log
import androidx.core.content.pm.PackageInfoCompat
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.AllowRuleEntity
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.RuntimeDnsSettingsRefresher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader

object DefaultWhitelistSeeder {
    private const val TAG = "DefaultWhitelistSeeder"
    const val SOURCE_PRESET = "preset"
    const val SOURCE_USER = "useradd"

    /**
     * Ensures preset default whitelist is initialized in the database.
     *
     * 以应用版本号为门控：每个版本仅在首次启动时灌入/重置一次预设白名单，
     * 同一版本内后续启动不再重复重置，避免覆盖用户此后的自定义修改。
     * 重置只清理 source=preset 的行，用户自建规则（useradd 等）不受影响。
     */
    suspend fun ensureInitialized(context: Context, database: AppDatabase) = withContext(Dispatchers.IO) {
        val currentVersion = currentVersionCode(context)
        if (AppSettings.isDefaultWhitelistInitialized(context) &&
            AppSettings.getDefaultWhitelistSeededVersion(context) == currentVersion
        ) {
            return@withContext
        }
        if (AppSettings.isDefaultWhitelistInitialized(context)) {
            Log.i(TAG, "App version changed to $currentVersion, resetting preset whitelist once...")
        } else {
            Log.i(TAG, "Initializing default preset whitelist...")
        }
        seed(context, database, forceReset = true)
        AppSettings.setDefaultWhitelistInitialized(context, true)
        AppSettings.setDefaultWhitelistSeededVersion(context, currentVersion)
        // 升级重置可能发生在 VPN 运行期间：让服务端白名单缓存与 Go 放行快照同步更新
        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
            context.applicationContext,
            refreshBlock = false,
            refreshAllow = true,
            refreshRewrite = false
        )
    }

    private fun currentVersionCode(context: Context): Long = runCatching {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        PackageInfoCompat.getLongVersionCode(packageInfo)
    }.getOrDefault(-1L)

    /**
     * Seeds or resets preset whitelist from assets/https_passthrough.txt.
     */
    suspend fun seed(context: Context, database: AppDatabase, forceReset: Boolean = false) = withContext(Dispatchers.IO) {
        val dao = database.allowRuleDao()
        if (forceReset) {
            dao.deleteBySource(SOURCE_PRESET)
        }

        val entries = parseAssetWhitelist(context)
        val now = System.currentTimeMillis()
        val entities = entries.map { (domain, category) ->
            AllowRuleEntity(
                pattern = domain,
                rawLine = domain,
                addedAt = now,
                enabled = true,
                groupName = category,
                appScope = null,
                appInverted = false,
                isWildcard = domain.contains('*'),
                important = false
            )
        }

        dao.insertAllForSource(entities, SOURCE_PRESET, sourceEnabled = true)
        Log.i(TAG, "Seeded ${entities.size} preset whitelist rules")
    }

    /**
     * Parses assets/https_passthrough.txt into a list of (domain, category).
     */
    fun parseAssetWhitelist(context: Context): List<Pair<String, String>> {
        val results = mutableListOf<Pair<String, String>>()
        val seen = mutableSetOf<String>()
        var currentCategory = "默认预设"

        runCatching {
            context.assets.open("https_passthrough.txt").use { inputStream ->
                BufferedReader(InputStreamReader(inputStream)).useLines { lines ->
                    for (rawLine in lines) {
                        val trimmed = rawLine.trim()
                        if (trimmed.isEmpty()) continue

                        if (trimmed.startsWith("#") || trimmed.startsWith("//")) {
                            val comment = trimmed.removePrefix("#").removePrefix("//").trim()
                            val cleanedHeader = comment.replace("─", "").trim()
                            if (cleanedHeader.isNotEmpty() && !cleanedHeader.startsWith("Format:") && !cleanedHeader.startsWith("Comment:") && !cleanedHeader.startsWith("Each entry") && !cleanedHeader.startsWith("Domains in") && !cleanedHeader.startsWith("BlockAds")) {
                                currentCategory = cleanedHeader
                            }
                            continue
                        }

                        val domain = trimmed.lowercase().trimEnd('.')
                        if (domain.isNotEmpty() && seen.add(domain)) {
                            results.add(domain to currentCategory)
                        }
                    }
                }
            }
        }.onFailure {
            Log.e(TAG, "Failed to read assets/https_passthrough.txt", it)
        }

        return results
    }
}
