package com.haoze.diting.ui.batch

import android.content.Context
import com.haoze.diting.data.RuleDataSources
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.BlockRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleKind
import com.haoze.diting.data.entity.RewriteRuleEntity
import com.haoze.diting.data.entity.RewriteTargetType
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.RuntimeDnsSettingsRefresher
import com.haoze.diting.vpn.AllowListManager
import com.haoze.diting.vpn.BlockListManager
import com.haoze.diting.vpn.CosmeticRuleManager
import com.haoze.diting.vpn.DefaultWhitelistSeeder
import com.haoze.diting.vpn.GoUrlRuleManager
import com.haoze.diting.vpn.RewriteRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Validates multiline text input for mixed Blacklist, Whitelist, and Rewrite rules.
 * Handles parsing, duplicate detection, and batch insertion.
 */
class BatchRuleValidator(
    private val database: RuleDataSources,
    private val dataset: RuleDataset,
    private val target: BatchRuleTarget = BatchRuleTarget.BLACKLIST
) {
    private val blockRuleDao = database.blockRuleDao()
    private val allowRuleDao = database.allowRuleDao()
    private val rewriteRuleDao = database.rewriteRuleDao()
    private val goUrlRuleDao = database.goUrlRuleDao()
    private val cosmeticRuleDao = database.cosmeticRuleDao()
    private val blockListManager = BlockListManager(blockRuleDao, scope = RuleScope.DNS)
    private val allowListManager = AllowListManager(allowRuleDao, scope = RuleScope.DNS)
    private val goUrlRuleManager = GoUrlRuleManager(goUrlRuleDao)
    private val rewriteRuleManager = RewriteRuleManager(rewriteRuleDao, scope = RuleScope.DNS)

    suspend fun validate(
        input: String,
        mode: BatchRecognitionMode = BatchRecognitionMode.fromTarget(target)
    ): BatchValidationSummary = withContext(Dispatchers.IO) {
        val lines = input.lines()
        val validItems = mutableListOf<BatchRuleItem>()
        val duplicateItems = mutableListOf<BatchRuleItem.Duplicate>()
        val invalidItems = mutableListOf<BatchRuleItem.Invalid>()
        var ignoredCount = 0

        val seenKeys = mutableSetOf<String>()

        lines.forEachIndexed { index, line ->
            val lineNo = index + 1
            val classifiedList = BatchRuleClassifier.classify(line, mode, dataset)

            for (classified in classifiedList) {
                when (classified) {
                    is ClassifiedLine.Ignored -> {
                        ignoredCount++
                    }
                    is ClassifiedLine.Invalid -> {
                        invalidItems.add(BatchRuleItem.Invalid(lineNo, line.trim(), classified.reason))
                    }
                    is ClassifiedLine.Domain -> {
                        validateDomain(lineNo, line.trim(), classified, seenKeys, validItems, duplicateItems)
                    }
                    is ClassifiedLine.Url -> {
                        validateUrl(lineNo, line.trim(), classified, seenKeys, validItems, duplicateItems)
                    }
                    is ClassifiedLine.Cosmetic -> {
                        validateCosmetic(lineNo, line.trim(), classified, seenKeys, validItems, duplicateItems)
                    }
                    is ClassifiedLine.Rewrite -> {
                        validateRewrite(lineNo, line.trim(), classified, seenKeys, validItems, duplicateItems, invalidItems)
                    }
                }
            }
        }

        BatchValidationSummary(
            target = target,
            mode = mode,
            totalLines = lines.size,
            validItems = validItems,
            duplicateItems = duplicateItems,
            invalidItems = invalidItems,
            ignoredCount = ignoredCount
        )
    }

    private suspend fun validateDomain(
        lineNo: Int,
        raw: String,
        classified: ClassifiedLine.Domain,
        seenKeys: MutableSet<String>,
        validItems: MutableList<BatchRuleItem>,
        duplicateItems: MutableList<BatchRuleItem.Duplicate>
    ) {
        val category = if (classified.isAllow) BatchRuleCategory.ALLOW else BatchRuleCategory.BLOCK
        val prefix = if (classified.isAllow) "allow" else "block"
        val key = "$prefix:${classified.pattern}:${classified.important}:${classified.appScope}:${classified.dnsType}:${classified.denyallow}:${classified.isRegex}"

        if (!seenKeys.add(key)) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则", category))
            return
        }

        val exists = if (classified.isAllow) {
            allowRuleDao.idByPattern(
                pattern = classified.pattern,
                important = classified.important,
                appScope = classified.appScope,
                appInverted = false,
                dnsType = classified.dnsType,
                isRegex = classified.isRegex
            ) > 0
        } else {
            blockRuleDao.idByPattern(
                pattern = classified.pattern,
                important = classified.important,
                appScope = classified.appScope,
                appInverted = false,
                dnsType = classified.dnsType,
                isRegex = classified.isRegex
            ) > 0
        }

        if (exists) {
            val reason = if (classified.isAllow) "白名单中已存在该规则" else "黑名单中已存在该规则"
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, reason, category))
            return
        }

        validItems.add(
            BatchRuleItem.ValidDomain(
                lineNumber = lineNo,
                rawLine = raw,
                pattern = classified.pattern,
                isAllow = classified.isAllow,
                appScope = classified.appScope,
                important = classified.important,
                isWildcard = classified.isWildcard,
                denyallow = classified.denyallow,
                isRegex = classified.isRegex,
                dnsType = classified.dnsType
            )
        )
    }

    private suspend fun validateUrl(
        lineNo: Int,
        raw: String,
        classified: ClassifiedLine.Url,
        seenKeys: MutableSet<String>,
        validItems: MutableList<BatchRuleItem>,
        duplicateItems: MutableList<BatchRuleItem.Duplicate>
    ) {
        val category = if (classified.isAllow) BatchRuleCategory.ALLOW else BatchRuleCategory.BLOCK
        val prefix = if (classified.isAllow) "url_allow" else "url_block"
        val key = "$prefix:${classified.urlPattern}"

        if (!seenKeys.add(key)) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则", category))
            return
        }

        val kind = if (classified.isAllow) GoUrlRuleKind.ALLOW else GoUrlRuleKind.BLOCK
        if (goUrlRuleDao.idByPattern(classified.urlPattern, kind) > 0) {
            val reason = if (classified.isAllow) "白名单中已存在该规则" else "黑名单中已存在该规则"
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, reason, category))
            return
        }

        validItems.add(
            BatchRuleItem.ValidUrl(
                lineNumber = lineNo,
                rawLine = raw,
                urlPattern = classified.urlPattern,
                isAllow = classified.isAllow
            )
        )
    }

    private suspend fun validateCosmetic(
        lineNo: Int,
        raw: String,
        classified: ClassifiedLine.Cosmetic,
        seenKeys: MutableSet<String>,
        validItems: MutableList<BatchRuleItem>,
        duplicateItems: MutableList<BatchRuleItem.Duplicate>
    ) {
        val category = if (classified.isException) BatchRuleCategory.ALLOW else BatchRuleCategory.BLOCK
        val key = "cosmetic:${classified.domain}:${classified.selector}:${classified.isException}"

        if (!seenKeys.add(key)) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则", category))
            return
        }

        if (cosmeticRuleDao.idByDomainAndSelector(classified.domain, classified.selector) > 0) {
            val reason = if (classified.isException) "白名单中已存在该规则" else "黑名单中已存在该规则"
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, reason, category))
            return
        }

        validItems.add(
            BatchRuleItem.ValidCosmetic(
                lineNumber = lineNo,
                rawLine = raw,
                domain = classified.domain,
                selector = classified.selector,
                isException = classified.isException
            )
        )
    }

    private suspend fun validateRewrite(
        lineNo: Int,
        raw: String,
        classified: ClassifiedLine.Rewrite,
        seenKeys: MutableSet<String>,
        validItems: MutableList<BatchRuleItem>,
        duplicateItems: MutableList<BatchRuleItem.Duplicate>,
        invalidItems: MutableList<BatchRuleItem.Invalid>
    ) {
        val domain = classified.domain
        val targetType = classified.targetType
        val targetValue = classified.targetValue
        val isCname = targetType == RewriteTargetType.CNAME

        if (isCname && rewriteRuleDao.countOtherTypes(domain, targetType) > 0) {
            invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "该域名已存在 IP 覆写规则，不能同时添加 CNAME: $domain"))
            return
        }
        if (!isCname && rewriteRuleDao.countType(domain, RewriteTargetType.CNAME) > 0) {
            invalidItems.add(BatchRuleItem.Invalid(lineNo, raw, "该域名已存在 CNAME 覆写规则，不能同时添加 IP: $domain"))
            return
        }

        val key = "rewrite:$domain:$targetType:$targetValue"
        if (!seenKeys.add(key)) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "输入中已存在相同规则", BatchRuleCategory.REWRITE))
            return
        }

        if (rewriteRuleDao.idByKey(domain, targetType, targetValue) > 0) {
            duplicateItems.add(BatchRuleItem.Duplicate(lineNo, raw, key, "覆写名单中已存在该规则", BatchRuleCategory.REWRITE))
            return
        }

        validItems.add(
            BatchRuleItem.ValidRewrite(
                lineNumber = lineNo,
                rawLine = classified.rawLine,
                domain = domain,
                targetType = targetType,
                targetValue = targetValue
            )
        )
    }

    suspend fun commitDetailed(context: Context, validItems: List<BatchRuleItem>): BatchCommitResult = withContext(Dispatchers.IO) {
        val now = System.currentTimeMillis()
        var blockInserted = 0
        var allowInserted = 0
        var rewriteInserted = 0

        val domainBlockItems = validItems.filterIsInstance<BatchRuleItem.ValidDomain>().filter { !it.isAllow }
        val domainAllowItems = validItems.filterIsInstance<BatchRuleItem.ValidDomain>().filter { it.isAllow }
        val urlBlockItems = validItems.filterIsInstance<BatchRuleItem.ValidUrl>().filter { !it.isAllow }
        val urlAllowItems = validItems.filterIsInstance<BatchRuleItem.ValidUrl>().filter { it.isAllow }
        val cosmeticItems = validItems.filterIsInstance<BatchRuleItem.ValidCosmetic>()
        val rewriteItems = validItems.filterIsInstance<BatchRuleItem.ValidRewrite>()

        // 1. Commit Blacklist Domain Rules
        if (domainBlockItems.isNotEmpty()) {
            val entities = domainBlockItems.map { item ->
                BlockRuleEntity(
                    pattern = item.pattern,
                    rawLine = item.rawLine,
                    addedAt = now,
                    enabled = true,
                    groupName = null,
                    appScope = item.appScope,
                    appInverted = false,
                    isWildcard = item.isWildcard,
                    denyallow = item.denyallow,
                    isRegex = item.isRegex,
                    dnsType = item.dnsType,
                    important = item.important
                )
            }
            blockInserted += blockRuleDao.insertAllForSource(entities, "useradd", sourceEnabled = true)
            domainBlockItems.forEach { blockListManager.syncCachedPattern(it.pattern) }
        }

        // 2. Commit Whitelist Domain Rules
        if (domainAllowItems.isNotEmpty()) {
            val entities = domainAllowItems.map { item ->
                AllowRuleEntity(
                    pattern = item.pattern,
                    rawLine = item.rawLine,
                    addedAt = now,
                    enabled = true,
                    groupName = null,
                    appScope = item.appScope,
                    appInverted = false,
                    isWildcard = item.isWildcard,
                    denyallow = item.denyallow,
                    isRegex = item.isRegex,
                    dnsType = item.dnsType,
                    important = item.important
                )
            }
            allowInserted += allowRuleDao.insertAllForSource(
                entities, DefaultWhitelistSeeder.SOURCE_USER, sourceEnabled = true
            )
            domainAllowItems.forEach { allowListManager.syncCachedPattern(it.pattern) }
        }

        // 3. Commit URL Rules
        urlBlockItems.forEach { item ->
            val entity = GoUrlRuleEntity(
                pattern = item.urlPattern,
                kind = GoUrlRuleKind.BLOCK,
                rawLine = item.rawLine,
                addedAt = now,
                enabled = true
            )
            if (goUrlRuleDao.insertForSource(entity, "useradd", sourceEnabled = true)) {
                blockInserted++
            }
        }

        urlAllowItems.forEach { item ->
            val entity = GoUrlRuleEntity(
                pattern = item.urlPattern,
                kind = GoUrlRuleKind.ALLOW,
                rawLine = item.rawLine,
                addedAt = now,
                enabled = true
            )
            if (goUrlRuleDao.insertForSource(entity, DefaultWhitelistSeeder.SOURCE_USER, sourceEnabled = true)) {
                allowInserted++
            }
        }

        // 4. Commit Cosmetic Rules
        cosmeticItems.forEach { item ->
            val entity = CosmeticRuleEntity(
                domain = item.domain,
                selector = item.selector,
                rawLine = item.rawLine,
                addedAt = now,
                enabled = true
            )
            val src = if (item.isException) DefaultWhitelistSeeder.SOURCE_USER else "useradd"
            if (cosmeticRuleDao.insertForSource(entity, src, sourceEnabled = true)) {
                if (item.isException) allowInserted++ else blockInserted++
            }
        }
        if (cosmeticItems.isNotEmpty()) {
            CosmeticRuleManager.getInstance(context).compileAllToCss()
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
        }

        // 5. Commit Rewrite Rules
        if (rewriteItems.isNotEmpty()) {
            val entities = rewriteItems.map { item ->
                RewriteRuleEntity(
                    pattern = item.domain,
                    targetType = item.targetType,
                    targetValue = item.targetValue,
                    rawLine = item.rawLine,
                    addedAt = now,
                    enabled = true
                )
            }
            rewriteInserted += rewriteRuleDao.insertAllForSource(entities, "useradd", enabled = true)
            rewriteRuleManager.refreshCache(rebuildSubscriptionIndex = false)
        }

        // 6. Refresh runtime DNS indexes for modified rule kinds
        val hasBlock = domainBlockItems.isNotEmpty() || urlBlockItems.isNotEmpty()
        val hasAllow = domainAllowItems.isNotEmpty() || urlAllowItems.isNotEmpty()
        val hasRewrite = rewriteItems.isNotEmpty()

        if (hasBlock || hasAllow || hasRewrite) {
            RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                context,
                refreshBlock = hasBlock,
                refreshAllow = hasAllow,
                refreshRewrite = hasRewrite,
                dataset = dataset
            )
        }

        BatchCommitResult(
            blockInserted = blockInserted,
            allowInserted = allowInserted,
            rewriteInserted = rewriteInserted
        )
    }

    suspend fun commit(context: Context, validItems: List<BatchRuleItem>): Int {
        return commitDetailed(context, validItems).totalInserted
    }
}
