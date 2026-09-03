package com.haoze.dnssr.vpn

import java.io.File
import org.json.JSONArray
import org.json.JSONObject

sealed interface DomainDecision {
    val authority: String
    val matchedRule: String?
    val isAppSpecific: Boolean

    data class Allow(
        override val authority: String,
        override val matchedRule: String? = null,
        override val isAppSpecific: Boolean = false
    ) : DomainDecision

    data class Block(
        override val authority: String,
        override val matchedRule: String,
        val source: String,
        override val isAppSpecific: Boolean = false
    ) : DomainDecision
}

/**
 * 域名策略决策引擎。
 *
 * 严格优先级决策矩阵：
 * 1. App 专用 $important 屏蔽规则（针对该 App 的最高优先级阻断）
 * 2. 全局 $important 屏蔽规则（全局最高优先级阻断）
 * 3. App 专用白名单规则（例如 @@||*.google.com^$app=com.google.android.gms...）
 * 4. 全局白名单规则
 * 5. App 专用常规屏蔽规则（包含应用默认全阻断 *$app=...）
 * 6. 全局常规屏蔽规则
 * 7. 默认放行（跟随全局放行策略）
 */
class DomainPolicy(
    private val allowListManager: AllowListManager,
    private val blockListManager: BlockListManager,
    private val isEnabledProvider: () -> Boolean = { true }
) {
    private val cacheLock = Any()
    private val decisionCache = android.util.LruCache<String, DomainDecision>(CACHE_CAPACITY)

    fun invalidateCache() {
        synchronized(cacheLock) {
            decisionCache.evictAll()
        }
    }

    fun evaluate(authority: String, packageName: String? = null): DomainDecision {
        if (!isEnabledProvider()) {
            return DomainDecision.Allow(authority)
        }
        val domain = authority.lowercase().trimEnd('.')
        if (domain.isEmpty()) return DomainDecision.Allow(authority)

        val targetPackage = packageName?.takeIf { it.isNotBlank() }
        val cacheKey = if (targetPackage != null) "$domain#$targetPackage" else domain

        synchronized(cacheLock) {
            decisionCache.get(cacheKey)
        }?.let { return it }

        val decision = evaluateInternal(authority, domain, targetPackage)
        synchronized(cacheLock) {
            decisionCache.put(cacheKey, decision)
        }
        return decision
    }

    private fun evaluateInternal(authority: String, domain: String, targetPackage: String?): DomainDecision {
        // 1. App 专用 $important 屏蔽规则 (Custom / Subscription)
        if (targetPackage != null) {
            blockListManager.findAppImportantMatch(domain, targetPackage)?.let { match ->
                return DomainDecision.Block(authority, match.pattern, match.source, isAppSpecific = true)
            }
        }

        // 2. 全局 $important 屏蔽规则 (Custom / Subscription)
        blockListManager.findGlobalImportantMatch(domain, targetPackage)?.let { match ->
            return DomainDecision.Block(authority, match.pattern, match.source, isAppSpecific = false)
        }

        // 3. App 专用白名单规则 (Custom / Subscription)
        if (targetPackage != null) {
            allowListManager.findAppMatch(domain, targetPackage)?.let { rule ->
                return DomainDecision.Allow(authority, rule, isAppSpecific = true)
            }
        }

        // 4. 全局白名单规则 (Custom / Subscription)
        allowListManager.findGlobalMatch(domain, targetPackage)?.let { rule ->
            return DomainDecision.Allow(authority, rule, isAppSpecific = false)
        }

        // 5. App 专用常规屏蔽规则 (Custom / Subscription, 包含 *$app=pkg 全阻断)
        if (targetPackage != null) {
            blockListManager.findAppMatch(domain, targetPackage)?.let { match ->
                return DomainDecision.Block(authority, match.pattern, match.source, isAppSpecific = true)
            }
        }

        // 6. 全局常规屏蔽规则 (Custom / Subscription)
        blockListManager.findGlobalMatch(domain, targetPackage)?.let { match ->
            return DomainDecision.Block(authority, match.pattern, match.source, isAppSpecific = false)
        }

        // 7. 默认放行
        return DomainDecision.Allow(authority)
    }

    /**
     * 生成供 Go 侧本地内存决策引擎读取的完整规则快照 JSON 字符串。
     */
    fun buildRuleSnapshotJson(ruleIndexDirectory: File? = null): String {
        val root = JSONObject()
        root.put("filterEnabled", isEnabledProvider())

        if (ruleIndexDirectory != null && ruleIndexDirectory.isDirectory) {
            val blockTrie = File(ruleIndexDirectory, "subscription-block.trie")
            if (blockTrie.exists() && blockTrie.length() > 0) {
                root.put("blockTriePath", blockTrie.absolutePath)
            }
            val impBlockTrie = File(ruleIndexDirectory, "subscription-block.trie.important")
            if (impBlockTrie.exists() && impBlockTrie.length() > 0) {
                root.put("importantBlockTriePath", impBlockTrie.absolutePath)
            }
            val allowTrie = File(ruleIndexDirectory, "subscription-allow.trie")
            if (allowTrie.exists() && allowTrie.length() > 0) {
                root.put("allowTriePath", allowTrie.absolutePath)
            }
        }

        val allowSnapshot = allowListManager.exportSnapshot()
        val blockSnapshot = blockListManager.exportSnapshot()

        // globalAllow
        val globalAllowArr = JSONArray()
        allowSnapshot.globalAllow.forEach { globalAllowArr.put(it) }
        root.put("globalAllow", globalAllowArr)

        // globalBlock
        val globalBlockArr = JSONArray()
        blockSnapshot.globalBlock.forEach { globalBlockArr.put(it) }
        root.put("globalBlock", globalBlockArr)

        // globalImportant
        val globalImpArr = JSONArray()
        blockSnapshot.globalImportant.forEach { globalImpArr.put(it) }
        root.put("globalImportant", globalImpArr)

        // appRules: map of pkg -> { allow: [...], block: [...], important: [...] }
        val allPkgs = LinkedHashSet<String>()
        allPkgs.addAll(allowSnapshot.appRules.keys)
        allPkgs.addAll(blockSnapshot.appRules.keys)

        val appRulesObj = JSONObject()
        for (pkg in allPkgs) {
            val appObj = JSONObject()
            val allows = allowSnapshot.appRules[pkg].orEmpty()
            val blockRules = blockSnapshot.appRules[pkg]

            val allowArr = JSONArray()
            allows.forEach { allowArr.put(it) }
            appObj.put("allow", allowArr)

            val blockArr = JSONArray()
            blockRules?.block.orEmpty().forEach { blockArr.put(it) }
            appObj.put("block", blockArr)

            val impArr = JSONArray()
            blockRules?.important.orEmpty().forEach { impArr.put(it) }
            appObj.put("important", impArr)

            appRulesObj.put(pkg, appObj)
        }
        root.put("appRules", appRulesObj)

        // invertedBlock: array of { pattern, source, important, excludedApps: [...] }
        val invBlockArr = JSONArray()
        for (rule in blockSnapshot.invertedRules) {
            val invObj = JSONObject()
            invObj.put("pattern", rule.pattern)
            invObj.put("source", rule.source)
            invObj.put("important", rule.important)
            val excArr = JSONArray()
            rule.excludedApps.forEach { excArr.put(it) }
            invObj.put("excludedApps", excArr)
            invBlockArr.put(invObj)
        }
        root.put("invertedBlock", invBlockArr)

        // invertedAllow: array of { pattern, excludedApps: [...] }
        val invAllowArr = JSONArray()
        for (rule in allowSnapshot.invertedRules) {
            val invObj = JSONObject()
            invObj.put("pattern", rule.pattern)
            val excArr = JSONArray()
            rule.excludedApps.forEach { excArr.put(it) }
            invObj.put("excludedApps", excArr)
            invAllowArr.put(invObj)
        }
        root.put("invertedAllow", invAllowArr)

        return root.toString()
    }

    companion object {
        private const val CACHE_CAPACITY = 8192
    }
}
