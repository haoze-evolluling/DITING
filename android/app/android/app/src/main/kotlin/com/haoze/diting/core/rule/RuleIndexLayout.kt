package com.haoze.diting.core.rule

import java.io.File

/**
 * Artifact paths of the rule index, relative to `filesDir`.
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
 * Every artifact here is pure derived data (rebuildable from the database at any time). The names
 * and the per-dataset root live in the kernel (`rust/diting-rule-core/src/index_layout.rs`), so the
 * stamp check, the engine's DTRI reader and this class cannot drift apart; only the `File` joining
 * stays here.
 */
internal object RuleIndexLayout {
    /// The dataset-independent tails, taken once (only `root` varies per dataset).
    private val normalPaths: RuleIndexPaths by lazy { RuleIndexNative.paths(RuleDataset.NORMAL) }

    private fun paths(dataset: RuleDataset): RuleIndexPaths = when (dataset) {
        RuleDataset.NORMAL, RuleDataset.DNS_MODE -> normalPaths
        RuleDataset.EXPRESS -> RuleIndexNative.paths(RuleDataset.EXPRESS)
    }

    /** Files root holding rule index artifacts. */
    fun rootDirectory(filesDir: File, dataset: RuleDataset = RuleDataset.NORMAL): File =
        File(filesDir, paths(dataset).root)

    /** Domain (blacklist / whitelist) artifacts of one data set. */
    fun domainDirectory(indexDirectory: File): File = File(indexDirectory, normalPaths.domain)

    /** Hosts (address / CNAME rewriting) artifacts; kept for path parity with the legacy layout. */
    fun hostsDirectory(indexDirectory: File): File = File(indexDirectory, normalPaths.hosts)

    fun blockIndex(indexDirectory: File): File = File(domainDirectory(indexDirectory), normalPaths.block)

    fun blockImportantIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), normalPaths.blockImportant)

    fun allowIndex(indexDirectory: File): File = File(domainDirectory(indexDirectory), normalPaths.allow)

    fun allowImportantIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), normalPaths.allowImportant)

    /** Deletes every artifact of one data set, forcing a full rebuild. */
    fun deleteAll(indexDirectory: File) {
        listOf(domainDirectory(indexDirectory), hostsDirectory(indexDirectory)).forEach { directory ->
            runCatching {
                if (directory.isDirectory) directory.listFiles()?.forEach { it.delete() }
            }
        }
    }
}
