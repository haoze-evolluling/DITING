package com.haoze.dnssr.vpn

import java.io.BufferedReader

/**
 * 分类规则（block/allow/rewrite）的流式导入器，订阅导入与本地文件导入共用：
 * 逐行解析、满 [chunkSize] 落库、回报已导入进度，最后汇总 [RuleImportSummary]。
 */
internal class CategorizedRuleStreamImporter(
    private val blockListManager: BlockListManager,
    private val allowListManager: AllowListManager,
    private val rewriteRuleManager: RewriteRuleManager,
    private val chunkSize: Int = CHUNK_SIZE
) {
    companion object {
        const val CHUNK_SIZE = 1000
    }

    /**
     * [onEmpty] 在没有任何可导入的有效规则时调用，由调用方决定抛出的异常。
     */
    suspend fun import(
        reader: BufferedReader,
        source: String,
        enabled: Boolean,
        refreshCache: Boolean = false,
        onEmpty: () -> Nothing,
        onProgress: (suspend (processed: Int) -> Unit)? = null
    ): RuleImportSummary {
        val blockBatch = ArrayList<AdGuardRuleParser.ParsedRule>(chunkSize)
        val allowBatch = ArrayList<AdGuardRuleParser.ParsedRule>(chunkSize)
        val rewriteBatch = ArrayList<RewriteRule>(chunkSize)
        var insertedBlock = 0
        var insertedAllow = 0
        var insertedRewrite = 0
        var parsedRules = 0
        var invalid = 0
        var unsupported = 0
        var processed = 0

        suspend fun flushBlock() {
            if (blockBatch.isEmpty()) return
            val inserted = blockListManager.addRulesBatch(blockBatch, source, chunkSize, enabled, refreshCache)
            insertedBlock += inserted
            processed += inserted
            blockBatch.clear()
            onProgress?.invoke(processed)
        }

        suspend fun flushAllow() {
            if (allowBatch.isEmpty()) return
            val inserted = allowListManager.addRulesBatch(allowBatch, source, chunkSize, enabled, refreshCache)
            insertedAllow += inserted
            processed += inserted
            allowBatch.clear()
            onProgress?.invoke(processed)
        }

        suspend fun flushRewrite() {
            if (rewriteBatch.isEmpty()) return
            val inserted = rewriteRuleManager.addRules(rewriteBatch, source, enabled, chunkSize, refreshCache)
            insertedRewrite += inserted
            processed += inserted
            rewriteBatch.clear()
            onProgress?.invoke(processed)
        }

        reader.useLines { lines ->
            lines.forEach { line ->
                val parsed = AdGuardRuleParser.parseCategorizedLine(line)
                invalid += parsed.invalidCount
                unsupported += parsed.unsupportedCount
                parsedRules += parsed.blockRules.size + parsed.allowRules.size + parsed.rewriteRules.size
                for (rule in parsed.blockRules) {
                    blockBatch += rule
                    if (blockBatch.size == chunkSize) flushBlock()
                }
                for (rule in parsed.allowRules) {
                    allowBatch += rule
                    if (allowBatch.size == chunkSize) flushAllow()
                }
                for (rule in parsed.rewriteRules) {
                    rewriteBatch += rule
                    if (rewriteBatch.size == chunkSize) flushRewrite()
                }
            }
        }
        flushBlock()
        flushAllow()
        flushRewrite()

        if (parsedRules == 0) onEmpty()
        val totalInserted = insertedBlock + insertedAllow + insertedRewrite
        return RuleImportSummary(
            blockCount = insertedBlock,
            allowCount = insertedAllow,
            rewriteCount = insertedRewrite,
            duplicateCount = (parsedRules - totalInserted).coerceAtLeast(0),
            invalidCount = invalid,
            unsupportedCount = unsupported
        )
    }
}
