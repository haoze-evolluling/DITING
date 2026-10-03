package com.haoze.diting.vpn

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
 * Domain policy decision engine.
 *
 * Strict priority decision matrix:
 * 1. Per-app $important block rules (highest-priority blocking for that app)
 * 2. Global $important block rules (highest-priority blocking overall)
 * 3. Per-app allowlist rules (e.g. @@||*.google.com^$app=com.google.android.gms...)
 * 4. Global allowlist rules
 * 5. Per-app regular block rules (including default-block-everything *$app=...)
 * 6. Global regular block rules
 * 7. Default allow (follows the global pass-through policy)
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
        // 1. Per-app $important block rules (custom / subscription)
        if (targetPackage != null) {
            blockListManager.findAppImportantMatch(domain, targetPackage)?.let { match ->
                return DomainDecision.Block(authority, match.pattern, match.source, isAppSpecific = true)
            }
        }

        // 2. Global $important block rules (custom / subscription)
        blockListManager.findGlobalImportantMatch(domain, targetPackage)?.let { match ->
            return DomainDecision.Block(authority, match.pattern, match.source, isAppSpecific = false)
        }

        // 3. Per-app allowlist rules (custom / subscription)
        if (targetPackage != null) {
            allowListManager.findAppMatch(domain, targetPackage)?.let { rule ->
                return DomainDecision.Allow(authority, rule, isAppSpecific = true)
            }
        }

        // 4. Global allowlist rules (custom / subscription)
        allowListManager.findGlobalMatch(domain, targetPackage)?.let { rule ->
            return DomainDecision.Allow(authority, rule, isAppSpecific = false)
        }

        // 5. Per-app regular block rules (custom / subscription, including *$app=pkg full blocks)
        if (targetPackage != null) {
            blockListManager.findAppMatch(domain, targetPackage)?.let { match ->
                return DomainDecision.Block(authority, match.pattern, match.source, isAppSpecific = true)
            }
        }

        // 6. Global regular block rules (custom / subscription)
        blockListManager.findGlobalMatch(domain, targetPackage)?.let { match ->
            return DomainDecision.Block(authority, match.pattern, match.source, isAppSpecific = false)
        }

        // 7. Default allow
        return DomainDecision.Allow(authority)
    }

    /**
     * Builds the complete rule snapshot JSON consumed by the Go-side
     * in-memory decision engine.
     */
    fun buildRuleSnapshotJson(ruleIndexDirectory: File? = null): String {
        val root = JSONObject()
        root.put("filterEnabled", isEnabledProvider())

        if (ruleIndexDirectory != null && ruleIndexDirectory.isDirectory) {
            // Paths come from RuleIndexLayout so this can never drift from the
            // layout the caches actually write to.
            val blockTrie = RuleIndexLayout.blockIndex(ruleIndexDirectory)
            if (blockTrie.exists() && blockTrie.length() > 0) {
                root.put("blockTriePath", blockTrie.absolutePath)
            }
            val impBlockTrie = RuleIndexLayout.blockImportantIndex(ruleIndexDirectory)
            if (impBlockTrie.exists() && impBlockTrie.length() > 0) {
                root.put("importantBlockTriePath", impBlockTrie.absolutePath)
            }
            val allowTrie = RuleIndexLayout.allowIndex(ruleIndexDirectory)
            if (allowTrie.exists() && allowTrie.length() > 0) {
                root.put("allowTriePath", allowTrie.absolutePath)
            }
            // Important allow rules of subscriptions live only in this index:
            // AllowRuleCache drops them from the exported fallback list once the
            // index exists, so omitting the path silently loses them.
            val impAllowTrie = RuleIndexLayout.allowImportantIndex(ruleIndexDirectory)
            if (impAllowTrie.exists() && impAllowTrie.length() > 0) {
                root.put("importantAllowTriePath", impAllowTrie.absolutePath)
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

        val disabledArr = JSONArray()
        blockSnapshot.disabledRules.forEach { disabledArr.put(it) }
        root.put("disabledRules", disabledArr)

        // specialBlock: array of { pattern, source, important, appScope, appInverted, isWildcard, denyallow, isRegex, dnsType }
        val specialBlockArr = JSONArray()
        for (rule in blockSnapshot.specialRules) {
            val obj = JSONObject()
            obj.put("pattern", rule.pattern)
            obj.put("source", rule.source)
            obj.put("important", rule.important)
            if (rule.appScope != null) obj.put("appScope", rule.appScope)
            obj.put("appInverted", rule.appInverted)
            obj.put("isWildcard", rule.isWildcard)
            if (rule.denyallow != null) obj.put("denyallow", rule.denyallow)
            obj.put("isRegex", rule.isRegex)
            if (rule.dnsType != null) obj.put("dnsType", rule.dnsType)
            specialBlockArr.put(obj)
        }
        root.put("specialBlock", specialBlockArr)

        // specialAllow: array of { pattern, important, appScope, appInverted, isWildcard, denyallow, isRegex, dnsType }
        val specialAllowArr = JSONArray()
        for (rule in allowSnapshot.specialRules) {
            val obj = JSONObject()
            obj.put("pattern", rule.pattern)
            obj.put("important", rule.important)
            if (rule.appScope != null) obj.put("appScope", rule.appScope)
            obj.put("appInverted", rule.appInverted)
            obj.put("isWildcard", rule.isWildcard)
            if (rule.denyallow != null) obj.put("denyallow", rule.denyallow)
            obj.put("isRegex", rule.isRegex)
            if (rule.dnsType != null) obj.put("dnsType", rule.dnsType)
            specialAllowArr.put(obj)
        }
        root.put("specialAllow", specialAllowArr)

        return root.toString()
    }

    companion object {
        private const val CACHE_CAPACITY = 8192
    }
}
