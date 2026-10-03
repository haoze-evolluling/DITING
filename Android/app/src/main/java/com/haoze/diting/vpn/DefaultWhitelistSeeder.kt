package com.haoze.diting.vpn

import android.content.Context
import android.util.Log
import androidx.core.content.pm.PackageInfoCompat
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.BufferedReader
import java.io.InputStreamReader

object DefaultWhitelistSeeder {
    private const val TAG = "DefaultWhitelistSeeder"
    const val SOURCE_PRESET = "preset"
    const val SOURCE_USER = "useradd"

    private const val PRESET_SCHEMA_VERSION = 2L

    /**
     * Ensures the preset default whitelist is initialized in the database.
     *
     * Gated by the app version and preset schema revision: seeds/resets the preset
     * whitelist only once when upgraded or when schema changes. Later launches
     * within the same version do not re-seed, so user customizations are preserved.
     * The reset only deletes rows with source=preset; user-created rules are untouched.
     */
    suspend fun ensureInitialized(context: Context, database: AppDatabase) = withContext(Dispatchers.IO) {
        val currentVersion = currentVersionCode(context)
        val targetSeedVersion = currentVersion * 1000L + PRESET_SCHEMA_VERSION
        if (AppRulesSettingsStore.isDefaultWhitelistInitialized(context) &&
            AppRulesSettingsStore.getDefaultWhitelistSeededVersion(context) == targetSeedVersion
        ) {
            return@withContext
        }
        if (AppRulesSettingsStore.isDefaultWhitelistInitialized(context)) {
            Log.i(TAG, "App version or preset schema changed (target: $targetSeedVersion), resetting preset whitelist...")
        } else {
            Log.i(TAG, "Initializing default preset whitelist...")
        }
        seed(context, database, forceReset = true)
        AppRulesSettingsStore.setDefaultWhitelistInitialized(context, true)
        AppRulesSettingsStore.setDefaultWhitelistSeededVersion(context, targetSeedVersion)
        // The upgrade reset can happen while the VPN is running: keep the
        // service-side allowlist cache and Go-side passthrough snapshot in sync.
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
                            if (cleanedHeader.isNotEmpty() && !cleanedHeader.startsWith("Format:") && !cleanedHeader.startsWith("Comment:") && !cleanedHeader.startsWith("Each entry") && !cleanedHeader.startsWith("Domains in")) {
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
