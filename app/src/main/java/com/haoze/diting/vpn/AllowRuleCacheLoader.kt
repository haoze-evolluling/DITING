package com.haoze.diting.vpn

import android.util.Log
import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.EnabledRule
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.util.forEachKeysetPage
import java.io.File

/**
 * Result of loading all allow rules (custom and subscription).
 */
internal data class AllowRuleReloadResult(
    val customRules: Set<String>,
    val importantCustomRules: Set<String>,
    val customWildcards: List<AdGuardRuleParser.WildcardPattern>,
    val importantCustomWildcards: List<AdGuardRuleParser.WildcardPattern>,
    val customAppBuckets: Map<String, AllowAppRuleBucket>,
    val invertedCustomRules: List<InvertedAllowRule>,
    val subscriptionFallback: Set<String>,
    val importantSubscriptionFallback: Set<String>,
    val subscriptionWildcards: List<AdGuardRuleParser.WildcardPattern>,
    val importantSubscriptionWildcards: List<AdGuardRuleParser.WildcardPattern>,
    val subscriptionAppBuckets: Map<String, AllowAppRuleBucket>,
    val invertedSubscriptionRules: List<InvertedAllowRule>,
    val subscriptionIndex: MappedSubscriptionRuleIndex?,
    val importantSubscriptionIndex: MappedSubscriptionRuleIndex?,
    val specialRules: List<ExportedSpecialAllowRule> = emptyList()
)

/**
 * Result of reloading only custom allow rules.
 */
internal data class CustomAllowRuleReloadResult(
    val customRules: Set<String>,
    val importantCustomRules: Set<String>,
    val customWildcards: List<AdGuardRuleParser.WildcardPattern>,
    val importantCustomWildcards: List<AdGuardRuleParser.WildcardPattern>,
    val customAppBuckets: Map<String, AllowAppRuleBucket>,
    val invertedCustomRules: List<InvertedAllowRule>,
    val specialRules: List<ExportedSpecialAllowRule> = emptyList()
)

/**
 * Loads allow rules from the database and compiles/loads the mmap index.
 */
internal object AllowRuleCacheLoader {
    private const val TAG = "AllowRuleCacheLoader"
    private const val ALLOW_INDEX_PAGE_SIZE = 2_000

    suspend fun loadAll(
        dao: AllowRuleDao,
        scope: RuleScope = RuleScope.DNS,
        forceRebuild: Boolean = false,
        indexFile: File? = null,
        importantIndexFile: File? = null
    ): AllowRuleReloadResult {
        val customResult = loadCustomRules(dao)

        val targetFile = indexFile
        val importantFile = importantIndexFile

        var mapped = targetFile?.let { file ->
            if (!forceRebuild && file.exists() && file.length() > 0) {
                runCatching { MappedSubscriptionRuleIndex.load(file) }
                    .onFailure { Log.w(TAG, "Existing subscription allow index invalid, will recompile", it) }
                    .getOrNull()
            } else null
        }

        var importantMapped = importantFile?.let { file ->
            if (!forceRebuild && file.exists() && file.length() > 0) {
                runCatching { MappedSubscriptionRuleIndex.load(file) }
                    .onFailure { Log.w(TAG, "Existing important subscription allow index invalid, will recompile", it) }
                    .getOrNull()
            } else null
        }

        if (mapped == null) {
            mapped = targetFile?.let { file ->
                runCatching {
                    MappedSubscriptionRuleIndex.compileAndLoad(file) { consume ->
                        dao.forEachSubscriptionRulePage { rule ->
                            if (!rule.important && !rule.isWildcard && !rule.pattern.contains('*') && rule.appScope.isNullOrEmpty() && !rule.appInverted &&
                                !rule.isRegex && rule.denyallow.isNullOrEmpty() && rule.dnsType.isNullOrEmpty()
                            ) {
                                consume(rule)
                            }
                        }
                    }
                }.onFailure { e ->
                    Log.e(TAG, "Failed to compile subscription allow index (${file.name})", e)
                }.getOrNull()
            }
        }

        if (importantMapped == null) {
            importantMapped = importantFile?.let { file ->
                runCatching {
                    MappedSubscriptionRuleIndex.compileAndLoad(file) { consume ->
                        dao.forEachSubscriptionRulePage { rule ->
                            if (rule.important && !rule.isWildcard && !rule.pattern.contains('*') && rule.appScope.isNullOrEmpty() && !rule.appInverted &&
                                !rule.isRegex && rule.denyallow.isNullOrEmpty() && rule.dnsType.isNullOrEmpty()
                            ) {
                                consume(rule)
                            }
                        }
                    }
                }.onFailure { e ->
                    Log.e(TAG, "Failed to compile important subscription allow index (${file.name})", e)
                }.getOrNull()
            }
        }

        val subFallback = HashSet<String>()
        val importantSubFallback = HashSet<String>()
        val subWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val importantSubWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val subBucketsMap = HashMap<String, MutableAllowAppBucket>()
        val subInvertedList = mutableListOf<InvertedAllowRule>()
        val subSpecialRules = mutableListOf<ExportedSpecialAllowRule>()

        fun processSubscriptionRule(entry: EnabledRule) {
            val isSpecial = entry.isRegex || !entry.denyallow.isNullOrEmpty() || !entry.dnsType.isNullOrEmpty()
            if (isSpecial) {
                subSpecialRules.add(
                    ExportedSpecialAllowRule(
                        pattern = entry.pattern,
                        important = entry.important,
                        appScope = entry.appScope,
                        appInverted = entry.appInverted,
                        isWildcard = entry.isWildcard || entry.pattern.contains('*'),
                        denyallow = entry.denyallow,
                        isRegex = entry.isRegex,
                        dnsType = entry.dnsType
                    )
                )
                return
            }

            val isWc = entry.isWildcard || entry.pattern.contains('*')
            val wcPattern = if (isWc) AdGuardRuleParser.WildcardPattern(entry.pattern) else null

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                val excluded = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                subInvertedList.add(InvertedAllowRule(entry.pattern, entry.important, excluded, wcPattern))
            } else if (!entry.appScope.isNullOrEmpty()) {
                val pkgs = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                for (pkg in pkgs) {
                    val bucket = subBucketsMap.getOrPut(pkg) { MutableAllowAppBucket() }
                    if (isWc && wcPattern != null) {
                        if (entry.important) bucket.importantWildcards.add(wcPattern)
                        else bucket.wildcards.add(wcPattern)
                    } else {
                        if (entry.important) bucket.importantExact.add(entry.pattern)
                        else bucket.exact.add(entry.pattern)
                    }
                }
            } else if (isWc && wcPattern != null) {
                if (entry.important) importantSubWc.add(wcPattern)
                else subWc.add(wcPattern)
            } else {
                if (entry.important) {
                    if (importantMapped == null) importantSubFallback.add(entry.pattern)
                } else {
                    if (mapped == null) subFallback.add(entry.pattern)
                }
            }
        }

        if (mapped != null && importantMapped != null) {
            dao.enabledSpecialSubscriptionRules().forEach(::processSubscriptionRule)
        } else {
            dao.forEachSubscriptionRulePage(::processSubscriptionRule)
        }

        return AllowRuleReloadResult(
            customRules = customResult.customRules,
            importantCustomRules = customResult.importantCustomRules,
            customWildcards = customResult.customWildcards,
            importantCustomWildcards = customResult.importantCustomWildcards,
            customAppBuckets = customResult.customAppBuckets,
            invertedCustomRules = customResult.invertedCustomRules,
            subscriptionFallback = subFallback,
            importantSubscriptionFallback = importantSubFallback,
            subscriptionWildcards = subWc,
            importantSubscriptionWildcards = importantSubWc,
            subscriptionAppBuckets = subBucketsMap.mapValues { it.value.toImmutable() },
            invertedSubscriptionRules = subInvertedList,
            subscriptionIndex = mapped,
            importantSubscriptionIndex = importantMapped,
            specialRules = customResult.specialRules + subSpecialRules
        )
    }

    suspend fun loadCustomRules(dao: AllowRuleDao): CustomAllowRuleReloadResult {
        val customRuleEntries = dao.enabledCustomRules()

        val custom = HashSet<String>()
        val importantCustom = HashSet<String>()
        val customWc = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val importantCustomWildcards = mutableListOf<AdGuardRuleParser.WildcardPattern>()
        val customBucketsMap = HashMap<String, MutableAllowAppBucket>()
        val customInvertedList = mutableListOf<InvertedAllowRule>()
        val customSpecialRules = mutableListOf<ExportedSpecialAllowRule>()

        for (entry in customRuleEntries) {
            val isSpecial = entry.isRegex || !entry.denyallow.isNullOrEmpty() || !entry.dnsType.isNullOrEmpty()
            if (isSpecial) {
                customSpecialRules.add(
                    ExportedSpecialAllowRule(
                        pattern = entry.pattern,
                        important = entry.important,
                        appScope = entry.appScope,
                        appInverted = entry.appInverted,
                        isWildcard = entry.isWildcard || entry.pattern.contains('*'),
                        denyallow = entry.denyallow,
                        isRegex = entry.isRegex,
                        dnsType = entry.dnsType
                    )
                )
                continue
            }

            val isWc = entry.isWildcard || entry.pattern.contains('*')
            val wcPattern = if (isWc) AdGuardRuleParser.WildcardPattern(entry.pattern) else null

            if (entry.appInverted && !entry.appScope.isNullOrEmpty()) {
                val excluded = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                customInvertedList.add(InvertedAllowRule(entry.pattern, entry.important, excluded, wcPattern))
            } else if (!entry.appScope.isNullOrEmpty()) {
                val pkgs = entry.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }
                for (pkg in pkgs) {
                    val bucket = customBucketsMap.getOrPut(pkg) { MutableAllowAppBucket() }
                    if (isWc && wcPattern != null) {
                        if (entry.important) bucket.importantWildcards.add(wcPattern)
                        else bucket.wildcards.add(wcPattern)
                    } else {
                        if (entry.important) bucket.importantExact.add(entry.pattern)
                        else bucket.exact.add(entry.pattern)
                    }
                }
            } else {
                if (isWc && wcPattern != null) {
                    if (entry.important) importantCustomWildcards.add(wcPattern)
                    else customWc.add(wcPattern)
                } else {
                    if (entry.important) importantCustom.add(entry.pattern)
                    else custom.add(entry.pattern)
                }
            }
        }

        return CustomAllowRuleReloadResult(
            customRules = custom,
            importantCustomRules = importantCustom,
            customWildcards = customWc,
            importantCustomWildcards = importantCustomWildcards,
            customAppBuckets = customBucketsMap.mapValues { it.value.toImmutable() },
            invertedCustomRules = customInvertedList,
            specialRules = customSpecialRules
        )
    }

    private suspend fun AllowRuleDao.forEachSubscriptionRulePage(
        consume: (EnabledRule) -> Unit
    ) = forEachKeysetPage(
        ALLOW_INDEX_PAGE_SIZE,
        { lastId, limit -> enabledSubscriptionRulesPageKeyset(limit, lastId) },
        { it.id },
        { consume(it.toEnabledRule()) }
    )
}

internal class MutableAllowAppBucket {
    val exact = HashSet<String>()
    val importantExact = HashSet<String>()
    val wildcards = mutableListOf<AdGuardRuleParser.WildcardPattern>()
    val importantWildcards = mutableListOf<AdGuardRuleParser.WildcardPattern>()

    fun toImmutable(): AllowAppRuleBucket = AllowAppRuleBucket(
        exactRules = exact,
        importantExactRules = importantExact,
        wildcardRules = wildcards,
        importantWildcardRules = importantWildcards
    )
}
