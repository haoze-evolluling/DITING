package com.haoze.diting.core.rule

import java.io.File

internal object RuleIndexLayout {
    private val normalPaths: RuleIndexPaths by lazy { RuleIndexNative.paths(RuleDataset.NORMAL) }
    private val expressPaths: RuleIndexPaths by lazy { RuleIndexNative.paths(RuleDataset.EXPRESS) }
    private val serverPaths: RuleIndexPaths by lazy { RuleIndexNative.paths(RuleDataset.SERVER) }

    private fun paths(dataset: RuleDataset): RuleIndexPaths = when (dataset) {
        RuleDataset.NORMAL -> normalPaths
        RuleDataset.EXPRESS -> expressPaths
        RuleDataset.SERVER -> serverPaths
    }

    fun rootDirectory(filesDir: File, dataset: RuleDataset = RuleDataset.NORMAL): File =
        File(filesDir, paths(dataset).root)

    fun domainDirectory(indexDirectory: File): File = File(indexDirectory, normalPaths.domain)

    fun hostsDirectory(indexDirectory: File): File = File(indexDirectory, normalPaths.hosts)

    fun blockIndex(indexDirectory: File): File = File(domainDirectory(indexDirectory), normalPaths.block)

    fun blockImportantIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), normalPaths.blockImportant)

    fun allowIndex(indexDirectory: File): File = File(domainDirectory(indexDirectory), normalPaths.allow)

    fun allowImportantIndex(indexDirectory: File): File =
        File(domainDirectory(indexDirectory), normalPaths.allowImportant)

    fun deleteAll(indexDirectory: File) {
        listOf(domainDirectory(indexDirectory), hostsDirectory(indexDirectory)).forEach { directory ->
            runCatching {
                if (directory.isDirectory) directory.listFiles()?.forEach { it.delete() }
            }
        }
    }
}
