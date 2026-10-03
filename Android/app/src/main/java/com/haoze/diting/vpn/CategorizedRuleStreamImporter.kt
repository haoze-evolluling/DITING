package com.haoze.diting.vpn

import com.haoze.diting.data.dao.CosmeticRuleDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleKind
import java.io.BufferedReader

/**
 * Streaming importer for categorized rules (block/allow/rewrite/url/cosmetic),
 * shared by subscription imports and local file imports: parses line by line, flushes
 * to the database every [chunkSize] rules, reports import progress, and
 * finally returns a [RuleImportSummary].
 */
internal class CategorizedRuleStreamImporter(
    private val blockListManager: BlockListManager,
    private val allowListManager: AllowListManager,
    private val rewriteRuleManager: RewriteRuleManager,
    private val goUrlRuleDao: GoUrlRuleDao? = null,
    private val cosmeticRuleDao: CosmeticRuleDao? = null,
    private val chunkSize: Int = CHUNK_SIZE
) {
    companion object {
        const val CHUNK_SIZE = 1000

        fun countRules(reader: BufferedReader, badfilterKeys: Set<String> = emptySet()): Int {
            var count = 0
            reader.forEachLine { line ->
                val parsed = AdGuardRuleParser.parseCategorizedLine(line)
                if (badfilterKeys.isEmpty()) {
                    count += parsed.blockRules.size + parsed.allowRules.size + parsed.rewriteRules.size +
                        parsed.urlBlockRules.size + parsed.urlAllowRules.size + parsed.cosmeticRules.size
                } else {
                    count += parsed.blockRules.count { AdGuardRuleParser.blockRuleKey(it) !in badfilterKeys } +
                        parsed.allowRules.count { AdGuardRuleParser.allowRuleKey(it) !in badfilterKeys } +
                        parsed.rewriteRules.count { AdGuardRuleParser.rewriteRuleKey(it) !in badfilterKeys } +
                        parsed.urlBlockRules.count { "url_block:${it.pattern}:${it.appScope}" !in badfilterKeys } +
                        parsed.urlAllowRules.count { "url_allow:${it.pattern}:${it.appScope}" !in badfilterKeys } +
                        parsed.cosmeticRules.size
                }
            }
            return count
        }

        fun countHostsRules(reader: BufferedReader): Int {
            var count = 0
            reader.forEachLine { line ->
                count += AdGuardRuleParser.parseHostsRewriteLine(line).size
            }
            return count
        }
    }

    /**
     * [onEmpty] is invoked when there is not a single importable valid rule;
     * its argument tells whether the source did contain rules of the other
     * type. The caller decides which exception to throw.
     */
    suspend fun import(
        reader: BufferedReader,
        source: String,
        kind: String,
        enabled: Boolean,
        refreshCache: Boolean = false,
        totalHint: Int = 0,
        badfilterKeys: Set<String> = emptySet(),
        onEmpty: (typeMismatchOnly: Boolean) -> Nothing,
        onProgress: (suspend (processed: Int, total: Int) -> Unit)? = null
    ): RuleImportSummary {
        val blockBatch = ArrayList<ParsedRule>(chunkSize)
        val allowBatch = ArrayList<ParsedRule>(chunkSize)
        val rewriteBatch = ArrayList<RewriteRule>(chunkSize)
        val urlBlockBatch = ArrayList<ParsedUrlRule>(chunkSize)
        val urlAllowBatch = ArrayList<ParsedUrlRule>(chunkSize)
        val cosmeticBatch = ArrayList<ParsedCosmeticRule>(chunkSize)

        var insertedBlock = 0
        var insertedAllow = 0
        var insertedRewrite = 0
        var insertedUrlBlock = 0
        var insertedUrlAllow = 0
        var insertedCosmetic = 0

        var parsedRules = 0
        var badfiltered = 0
        var invalid = 0
        var unsupported = 0
        var typeSkipped = 0
        var processed = 0

        suspend fun flushBlock() {
            if (blockBatch.isEmpty()) return
            val inserted = blockListManager.addRulesBatch(blockBatch, source, chunkSize, enabled, refreshCache)
            insertedBlock += inserted
            processed += inserted
            blockBatch.clear()
            onProgress?.invoke(processed, totalHint)
        }

        suspend fun flushAllow() {
            if (allowBatch.isEmpty()) return
            val inserted = allowListManager.addRulesBatch(allowBatch, source, chunkSize, enabled, refreshCache)
            insertedAllow += inserted
            processed += inserted
            allowBatch.clear()
            onProgress?.invoke(processed, totalHint)
        }

        suspend fun flushRewrite() {
            if (rewriteBatch.isEmpty()) return
            val inserted = rewriteRuleManager.addRules(rewriteBatch, source, enabled, chunkSize, refreshCache)
            insertedRewrite += inserted
            processed += inserted
            rewriteBatch.clear()
            onProgress?.invoke(processed, totalHint)
        }

        suspend fun flushUrlBlock() {
            if (urlBlockBatch.isEmpty()) return
            val dao = goUrlRuleDao
            if (dao != null) {
                val now = System.currentTimeMillis()
                for (rule in urlBlockBatch) {
                    val entity = GoUrlRuleEntity(
                        pattern = rule.pattern,
                        kind = GoUrlRuleKind.BLOCK,
                        rawLine = rule.rawLine,
                        addedAt = now,
                        enabled = enabled
                    )
                    if (dao.insertForSource(entity, source, enabled)) {
                        insertedUrlBlock++
                    }
                }
            }
            processed += urlBlockBatch.size
            urlBlockBatch.clear()
            onProgress?.invoke(processed, totalHint)
        }

        suspend fun flushUrlAllow() {
            if (urlAllowBatch.isEmpty()) return
            val dao = goUrlRuleDao
            if (dao != null) {
                val now = System.currentTimeMillis()
                for (rule in urlAllowBatch) {
                    val entity = GoUrlRuleEntity(
                        pattern = rule.pattern,
                        kind = GoUrlRuleKind.ALLOW,
                        rawLine = rule.rawLine,
                        addedAt = now,
                        enabled = enabled
                    )
                    if (dao.insertForSource(entity, source, enabled)) {
                        insertedUrlAllow++
                    }
                }
            }
            processed += urlAllowBatch.size
            urlAllowBatch.clear()
            onProgress?.invoke(processed, totalHint)
        }

        suspend fun flushCosmetic() {
            if (cosmeticBatch.isEmpty()) return
            val dao = cosmeticRuleDao
            if (dao != null) {
                val now = System.currentTimeMillis()
                for (rule in cosmeticBatch) {
                    val entity = CosmeticRuleEntity(
                        domain = rule.domain,
                        selector = rule.selector,
                        rawLine = rule.rawLine,
                        addedAt = now,
                        enabled = enabled
                    )
                    if (dao.insertForSource(entity, source, enabled)) {
                        insertedCosmetic++
                    }
                }
            }
            processed += cosmeticBatch.size
            cosmeticBatch.clear()
            onProgress?.invoke(processed, totalHint)
        }

        reader.useLines { lines ->
            lines.forEach { line ->
                val parsed = AdGuardRuleParser.parseCategorizedLine(line)
                invalid += parsed.invalidCount
                unsupported += parsed.unsupportedCount

                val lineRuleCount = parsed.blockRules.size + parsed.allowRules.size + parsed.rewriteRules.size +
                    parsed.urlBlockRules.size + parsed.urlAllowRules.size + parsed.cosmeticRules.size
                parsedRules += lineRuleCount

                for (rule in parsed.blockRules) {
                    if (badfilterKeys.isNotEmpty() && AdGuardRuleParser.blockRuleKey(rule) in badfilterKeys) {
                        badfiltered++
                    } else {
                        blockBatch += rule
                        if (blockBatch.size == chunkSize) flushBlock()
                    }
                }
                for (rule in parsed.allowRules) {
                    if (badfilterKeys.isNotEmpty() && AdGuardRuleParser.allowRuleKey(rule) in badfilterKeys) {
                        badfiltered++
                    } else {
                        allowBatch += rule
                        if (allowBatch.size == chunkSize) flushAllow()
                    }
                }
                for (rule in parsed.rewriteRules) {
                    if (badfilterKeys.isNotEmpty() && AdGuardRuleParser.rewriteRuleKey(rule) in badfilterKeys) {
                        badfiltered++
                    } else {
                        rewriteBatch += rule
                        if (rewriteBatch.size == chunkSize) flushRewrite()
                    }
                }
                for (rule in parsed.urlBlockRules) {
                    val key = "url_block:${rule.pattern}:${rule.appScope}"
                    if (badfilterKeys.isNotEmpty() && key in badfilterKeys) {
                        badfiltered++
                    } else {
                        urlBlockBatch += rule
                        if (urlBlockBatch.size == chunkSize) flushUrlBlock()
                    }
                }
                for (rule in parsed.urlAllowRules) {
                    val key = "url_allow:${rule.pattern}:${rule.appScope}"
                    if (badfilterKeys.isNotEmpty() && key in badfilterKeys) {
                        badfiltered++
                    } else {
                        urlAllowBatch += rule
                        if (urlAllowBatch.size == chunkSize) flushUrlAllow()
                    }
                }
                for (rule in parsed.cosmeticRules) {
                    cosmeticBatch += rule
                    if (cosmeticBatch.size == chunkSize) flushCosmetic()
                }
            }
        }
        flushBlock()
        flushAllow()
        flushRewrite()
        flushUrlBlock()
        flushUrlAllow()
        flushCosmetic()

        if (parsedRules == 0) onEmpty(typeSkipped > 0)
        val totalInserted = insertedBlock + insertedAllow + insertedRewrite +
            insertedUrlBlock + insertedUrlAllow + insertedCosmetic
        val finalTotal = if (totalHint > 0) totalHint else totalInserted
        onProgress?.invoke(finalTotal, finalTotal)

        return RuleImportSummary(
            blockCount = insertedBlock,
            allowCount = insertedAllow,
            rewriteCount = insertedRewrite,
            urlBlockCount = insertedUrlBlock,
            urlAllowCount = insertedUrlAllow,
            cosmeticCount = insertedCosmetic,
            duplicateCount = (parsedRules - totalInserted - badfiltered).coerceAtLeast(0),
            invalidCount = invalid,
            unsupportedCount = unsupported,
            typeSkippedCount = typeSkipped,
            badfilteredCount = badfiltered
        )
    }

    /**
     * Performs a two-pass import on a reusable reader provider:
     * 1. First pass scans for any `$badfilter` keys.
     * 2. Second pass parses and imports rules, skipping those invalidated by badfilter.
     */
    suspend fun importTwoPass(
        openReader: () -> BufferedReader,
        source: String,
        kind: String,
        enabled: Boolean,
        refreshCache: Boolean = false,
        totalHint: Int = 0,
        onEmpty: (typeMismatchOnly: Boolean) -> Nothing,
        onProgress: (suspend (processed: Int, total: Int) -> Unit)? = null
    ): RuleImportSummary {
        val badfilterKeys = openReader().use { AdGuardRuleParser.extractBadfilterKeys(it) }
        return openReader().use { reader ->
            import(
                reader = reader,
                source = source,
                kind = kind,
                enabled = enabled,
                refreshCache = refreshCache,
                totalHint = totalHint,
                badfilterKeys = badfilterKeys,
                onEmpty = onEmpty,
                onProgress = onProgress
            )
        }
    }
}
