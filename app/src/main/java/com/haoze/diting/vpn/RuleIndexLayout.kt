package com.haoze.diting.vpn

import android.util.Log
import com.haoze.diting.data.entity.RuleScope
import java.io.File

/**
 * Single source of truth for rule index artifact paths.
 *
 * Artifacts are grouped by subscription rule type, then by scope:
 *
 * ```
 * filesDir/rule-index/                 # DNS scope
 *   domain/block.trie                  # blacklist, non-important
 *   domain/block.important.trie
 *   domain/allow.trie                  # whitelist, non-important
 *   domain/allow.important.trie
 *   hosts/rewrite.trie                 # address / CNAME rewriting
 * filesDir/rule-index/https/           # HTTPS scope, same structure
 * ```
 *
 * Callers pass an already scope-resolved directory, so the same layout is
 * reused verbatim by both scopes; [scopeDirectory] resolves it for them.
 *
 * Every artifact here is pure derived data (rebuildable from the database at
 * any time), which is what makes [migrateLegacyLayout] safe: it only ever
 * renames or deletes files, and a file it fails to move simply gets rebuilt.
 */
internal object RuleIndexLayout {

    private const val TAG = "RuleIndexLayout"

    private const val ROOT_DIR_NAME = "rule-index"
    private const val HTTPS_DIR_NAME = "https"
    private const val DOMAIN_DIR_NAME = "domain"
    private const val HOSTS_DIR_NAME = "hosts"

    private const val BLOCK_INDEX_NAME = "block.trie"
    private const val BLOCK_IMPORTANT_INDEX_NAME = "block.important.trie"
    private const val ALLOW_INDEX_NAME = "allow.trie"
    private const val ALLOW_IMPORTANT_INDEX_NAME = "allow.important.trie"
    private const val HOSTS_INDEX_NAME = "rewrite.trie"

    // Flat artifact names used before the type split.
    private const val LEGACY_BLOCK_INDEX_NAME = "subscription-block.trie"
    private const val LEGACY_BLOCK_IMPORTANT_INDEX_NAME = "subscription-block.trie.important"
    private const val LEGACY_ALLOW_INDEX_NAME = "subscription-allow.trie"
    private const val LEGACY_ALLOW_IMPORTANT_INDEX_NAME = "subscription-allow.trie.important"
    private const val LEGACY_HOSTS_INDEX_NAME = "subscription-rewrite.trie"

    // ---------------------------------------------------------------- scopes

    /** Files root holding every scope's index artifacts. */
    fun rootDirectory(filesDir: File): File = File(filesDir, ROOT_DIR_NAME)

    /**
     * Directory holding one scope's artifacts. DNS owns the root itself so a
     * fresh install never needs an extra directory level.
     */
    fun scopeDirectory(filesDir: File, scope: RuleScope): File =
        if (scope == RuleScope.HTTPS) File(rootDirectory(filesDir), HTTPS_DIR_NAME) else rootDirectory(filesDir)

    /** Every scope directory that may hold artifacts. */
    fun allScopeDirectories(filesDir: File): List<File> =
        listOf(scopeDirectory(filesDir, RuleScope.DNS), scopeDirectory(filesDir, RuleScope.HTTPS))

    // ------------------------------------------------------------- artifacts

    /** Domain (blacklist / whitelist) artifacts, shared by one scope. */
    fun domainDirectory(indexDirectory: File): File = File(indexDirectory, DOMAIN_DIR_NAME)

    /** Hosts (address / CNAME rewriting) artifacts, shared by one scope. */
    fun hostsDirectory(indexDirectory: File): File = File(indexDirectory, HOSTS_DIR_NAME)

    fun blockIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), BLOCK_INDEX_NAME)

    fun blockImportantIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), BLOCK_IMPORTANT_INDEX_NAME)

    fun allowIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), ALLOW_INDEX_NAME)

    fun allowImportantIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), ALLOW_IMPORTANT_INDEX_NAME)

    fun hostsIndex(indexDirectory: File): File =
        File(hostsDirectory(indexDirectory), HOSTS_INDEX_NAME)

    // ------------------------------------------------------ legacy migration

    /**
     * Old flat artifacts and where they belong in the current layout. Renamed
     * rather than deleted so an upgrade keeps its compiled indexes and pays no
     * rebuild cost.
     */
    private val RENAMED_ARTIFACTS: List<Pair<String, Pair<String, String>>> = listOf(
        LEGACY_BLOCK_INDEX_NAME to (DOMAIN_DIR_NAME to BLOCK_INDEX_NAME),
        LEGACY_BLOCK_IMPORTANT_INDEX_NAME to (DOMAIN_DIR_NAME to BLOCK_IMPORTANT_INDEX_NAME),
        LEGACY_ALLOW_INDEX_NAME to (DOMAIN_DIR_NAME to ALLOW_INDEX_NAME),
        LEGACY_ALLOW_IMPORTANT_INDEX_NAME to (DOMAIN_DIR_NAME to ALLOW_IMPORTANT_INDEX_NAME),
        LEGACY_HOSTS_INDEX_NAME to (HOSTS_DIR_NAME to HOSTS_INDEX_NAME)
    )

    /**
     * Artifacts of layouts that no longer have a counterpart. They carry no
     * data of their own, so deleting them is enough.
     */
    private val ABANDONED_ARTIFACTS: List<String> = listOf(
        "dns-subscription-rewrite.trie",
        "https-subscription-rewrite.trie"
    )

    /** Old flat artifact names that belonged to the domain (block / allow) type. */
    fun legacyDomainFiles(indexDirectory: File): List<File> = listOf(
        File(indexDirectory, LEGACY_BLOCK_INDEX_NAME),
        File(indexDirectory, LEGACY_BLOCK_IMPORTANT_INDEX_NAME),
        File(indexDirectory, LEGACY_ALLOW_INDEX_NAME),
        File(indexDirectory, LEGACY_ALLOW_IMPORTANT_INDEX_NAME)
    )

    /** Old flat artifact names that belonged to the hosts (rewrite) type. */
    fun legacyHostsFiles(indexDirectory: File): List<File> =
        listOf(File(indexDirectory, LEGACY_HOSTS_INDEX_NAME)) +
            ABANDONED_ARTIFACTS.map { File(indexDirectory, it) }

    /** Moves every scope's artifacts from the old flat layout into the new one. */
    fun migrateLegacyLayout(filesDir: File) {
        allScopeDirectories(filesDir).forEach { indexDirectory ->
            runCatching { migrateScope(indexDirectory) }
                .onFailure { Log.w(TAG, "Rule index layout migration failed for ${indexDirectory.path}", it) }
        }
    }

    private fun migrateScope(indexDirectory: File) {
        if (!indexDirectory.isDirectory) return

        ABANDONED_ARTIFACTS.forEach { name ->
            runCatching { File(indexDirectory, name).takeIf { it.exists() }?.delete() }
        }

        RENAMED_ARTIFACTS.forEach { (legacyName, target) ->
            val source = File(indexDirectory, legacyName)
            if (!source.exists()) return@forEach

            val destination = File(File(indexDirectory, target.first), target.second)
            if (destination.exists()) {
                // The current layout already holds the artifact, so the flat
                // copy is a leftover from a previous run.
                runCatching { source.delete() }
                return@forEach
            }

            destination.parentFile?.mkdirs()
            val moved = runCatching { source.renameTo(destination) }.getOrDefault(false)
            if (moved) {
                Log.i(TAG, "Migrated rule index ${source.name} -> ${target.first}/${target.second}")
            } else {
                // Same filesystem, so this is unexpected; dropping the stale
                // file just means the index gets recompiled.
                Log.w(TAG, "Could not migrate rule index ${source.path}, deleting it to force a rebuild")
                runCatching { source.delete() }
            }
        }
    }

    /** Deletes stale artifacts. Never throws; a failed delete is harmless. */
    fun deleteLegacyFiles(indexDirectory: File) {
        (legacyDomainFiles(indexDirectory) + legacyHostsFiles(indexDirectory)).forEach { file ->
            runCatching {
                if (file.exists()) file.delete()
            }
        }
    }

    /** Deletes every artifact of one scope, forcing a full rebuild. */
    fun deleteAll(indexDirectory: File) {
        deleteLegacyFiles(indexDirectory)
        listOf(domainDirectory(indexDirectory), hostsDirectory(indexDirectory)).forEach { directory ->
            runCatching {
                if (directory.isDirectory) directory.listFiles()?.forEach { it.delete() }
            }
        }
    }
}
