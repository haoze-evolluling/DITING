package com.haoze.diting.core.rule

import java.io.File

/**
 * Single source of truth for rule index artifact paths, ported verbatim from the legacy app.
 *
 * Artifacts are grouped by subscription rule type:
 *
 * ```
 * filesDir/rule-index/                 # NORMAL dataset
 *   domain/block.trie                  # blacklist, non-important
 *   domain/block.important.trie
 *   domain/allow.trie                  # whitelist, non-important
 *   domain/allow.important.trie
 * filesDir/rule-index/express/         # EXPRESS dataset, same structure
 * ```
 *
 * Every artifact here is pure derived data (rebuildable from the database at any time).
 */
internal object RuleIndexLayout {

    private const val ROOT_DIR_NAME = "rule-index"
    private const val DOMAIN_DIR_NAME = "domain"
    private const val HOSTS_DIR_NAME = "hosts"

    private const val BLOCK_INDEX_NAME = "block.trie"
    private const val BLOCK_IMPORTANT_INDEX_NAME = "block.important.trie"
    private const val ALLOW_INDEX_NAME = "allow.trie"
    private const val ALLOW_IMPORTANT_INDEX_NAME = "allow.important.trie"

    /** Files root holding rule index artifacts. */
    fun rootDirectory(filesDir: File, dataset: RuleDataset = RuleDataset.NORMAL): File = when (dataset) {
        RuleDataset.NORMAL -> File(filesDir, ROOT_DIR_NAME)
        RuleDataset.EXPRESS -> File(File(filesDir, ROOT_DIR_NAME), "express")
        RuleDataset.DNS_MODE -> File(filesDir, ROOT_DIR_NAME)
    }

    /** Domain (blacklist / whitelist) artifacts of one data set. */
    fun domainDirectory(indexDirectory: File): File = File(indexDirectory, DOMAIN_DIR_NAME)

    /** Hosts (address / CNAME rewriting) artifacts; kept for path parity with the legacy layout. */
    fun hostsDirectory(indexDirectory: File): File = File(indexDirectory, HOSTS_DIR_NAME)

    fun blockIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), BLOCK_INDEX_NAME)

    fun blockImportantIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), BLOCK_IMPORTANT_INDEX_NAME)

    fun allowIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), ALLOW_INDEX_NAME)

    fun allowImportantIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), ALLOW_IMPORTANT_INDEX_NAME)

    /** Deletes every artifact of one data set, forcing a full rebuild. */
    fun deleteAll(indexDirectory: File) {
        listOf(domainDirectory(indexDirectory), hostsDirectory(indexDirectory)).forEach { directory ->
            runCatching {
                if (directory.isDirectory) directory.listFiles()?.forEach { it.delete() }
            }
        }
    }
}
