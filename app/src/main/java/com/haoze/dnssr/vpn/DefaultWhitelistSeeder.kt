package com.haoze.dnssr.vpn

import android.content.Context
import android.util.Log
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.AllowRuleEntity
import com.haoze.dnssr.ui.AppSettings
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
     */
    suspend fun ensureInitialized(context: Context, database: AppDatabase) = withContext(Dispatchers.IO) {
        if (!AppSettings.isDefaultWhitelistInitialized(context)) {
            Log.i(TAG, "Initializing default preset whitelist...")
            seed(context, database, forceReset = false)
            AppSettings.setDefaultWhitelistInitialized(context, true)
        }
    }

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
