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

        val disabledArr = JSONArray()
        blockSnapshot.disabledRules.forEach { disabledArr.put(it) }
        root.put("disabledRules", disabledArr)

        return root.toString()
    }

    companion object {
        private const val CACHE_CAPACITY = 8192
    }
}
