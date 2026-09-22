package com.haoze.diting.vpn

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
 * any time).
 */
internal object RuleIndexLayout {

    private const val ROOT_DIR_NAME = "rule-index"
    private const val HTTPS_DIR_NAME = "https"
    private const val DOMAIN_DIR_NAME = "domain"
    private const val HOSTS_DIR_NAME = "hosts"

    private const val BLOCK_INDEX_NAME = "block.trie"
    private const val BLOCK_IMPORTANT_INDEX_NAME = "block.important.trie"
    private const val ALLOW_INDEX_NAME = "allow.trie"
    private const val ALLOW_IMPORTANT_INDEX_NAME = "allow.important.trie"
    private const val HOSTS_INDEX_NAME = "rewrite.trie"

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

    /** Deletes every artifact of one scope, forcing a full rebuild. */
    fun deleteAll(indexDirectory: File) {
        listOf(domainDirectory(indexDirectory), hostsDirectory(indexDirectory)).forEach { directory ->
            runCatching {
                if (directory.isDirectory) directory.listFiles()?.forEach { it.delete() }
            }
        }
    }
}

