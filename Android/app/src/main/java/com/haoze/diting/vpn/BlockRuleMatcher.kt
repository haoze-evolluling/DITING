package com.haoze.diting.vpn

/**
 * Pure evaluation engine for block rule matching.
 */
internal object BlockRuleMatcher {

    /**
     * Matches in O(number of domain labels).
     */
    fun findMatch(state: BlockRuleCacheState, qname: String, packageName: String? = null): BlockRuleMatch? {
        return findImportantCustomMatch(state, qname, packageName)
            ?: findImportantSubscriptionMatch(state, qname, packageName)
            ?: findCustomMatch(state, qname, packageName)
            ?: findSubscriptionMatch(state, qname, packageName)
    }

    /**
     * Per-app $important block rule matching (priority 1).
     */
    fun findAppImportantMatch(state: BlockRuleCacheState, qname: String, packageName: String): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty() || packageName.isEmpty()) return null

        findInAppBucket(state.customAppBuckets, packageName, domain, important = true)?.let { return it }
        findInAppBucket(state.subscriptionAppBuckets, packageName, domain, important = true)?.let { return it }
        findInSpecialRules(state.specialRules, domain, packageName, important = true, appSpecific = true)?.let { return it }

        return null
    }

    /**
     * Global $important block rule matching (priority 2).
     */
    fun findGlobalImportantMatch(state: BlockRuleCacheState, qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInInvertedRules(state.invertedCustomRules, domain, important = true, packageName)?.let { return it }

        findInMap(domain, state.importantCustomRules)?.let { return it }
        findInWildcards(domain, state.importantCustomWildcards)?.let { return it }

        findInInvertedRules(state.invertedSubscriptionRules, domain, important = true, packageName)?.let { return it }

        findInSpecialRules(state.specialRules, domain, packageName, important = true, appSpecific = false)?.let { return it }

        return findSubscriptionTail(state, domain, important = true)
    }

    /**
     * Per-app regular block rule matching (priority 5; includes full-domain
     * blocks declared with *$app=pkg).
     */
    fun findAppMatch(state: BlockRuleCacheState, qname: String, packageName: String): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty() || packageName.isEmpty()) return null

        findInAppBucket(state.customAppBuckets, packageName, domain, important = false)?.let { return it }
        findInAppBucket(state.subscriptionAppBuckets, packageName, domain, important = false)?.let { return it }
        findInSpecialRules(state.specialRules, domain, packageName, important = false, appSpecific = true)?.let { return it }

        return null
    }

    /**
     * Global regular block rule matching (priority 6).
     */
    fun findGlobalMatch(state: BlockRuleCacheState, qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInInvertedRules(state.invertedCustomRules, domain, important = false, packageName)?.let { return it }

        findInMap(domain, state.customRules)?.let { return it }
        findInWildcards(domain, state.customWildcards)?.let { return it }

        findInInvertedRules(state.invertedSubscriptionRules, domain, important = false, packageName)?.let { return it }

        findInSpecialRules(state.specialRules, domain, packageName, important = false, appSpecific = false)?.let { return it }

        return findSubscriptionTail(state, domain, important = false)
    }

    fun findCustomMatch(state: BlockRuleCacheState, qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(state.customAppBuckets, packageName, domain, important = false)?.let { return it }

        findInInvertedRules(state.invertedCustomRules, domain, important = false, packageName)?.let { return it }

        return findInMap(domain, state.customRules) ?: findInWildcards(domain, state.customWildcards)
    }

    fun findImportantCustomMatch(state: BlockRuleCacheState, qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(state.customAppBuckets, packageName, domain, important = true)?.let { return it }

        findInInvertedRules(state.invertedCustomRules, domain, important = true, packageName)?.let { return it }

        return findInMap(domain, state.importantCustomRules) ?: findInWildcards(domain, state.importantCustomWildcards)
    }

    fun findSubscriptionMatch(state: BlockRuleCacheState, qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(state.subscriptionAppBuckets, packageName, domain, important = false)?.let { return it }

        findInInvertedRules(state.invertedSubscriptionRules, domain, important = false, packageName)?.let { return it }

        return findSubscriptionTail(state, domain, important = false)
    }

    fun findImportantSubscriptionMatch(state: BlockRuleCacheState, qname: String, packageName: String? = null): BlockRuleMatch? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(state.subscriptionAppBuckets, packageName, domain, important = true)?.let { return it }

        findInInvertedRules(state.invertedSubscriptionRules, domain, important = true, packageName)?.let { return it }

        return findSubscriptionTail(state, domain, important = true)
    }

    /** Matches within the given app's rule bucket in exact-then-wildcard order. */
    private fun findInAppBucket(
        buckets: Map<String, BlockAppRuleBucket>,
        packageName: String?,
        domain: String,
        important: Boolean
    ): BlockRuleMatch? {
        val bucket = packageName?.let { buckets[it] } ?: return null
        val exact = if (important) bucket.importantExactRules else bucket.exactRules
        val wildcards = if (important) bucket.importantWildcardRules else bucket.wildcardRules
        return findInMap(domain, exact) ?: findInWildcards(domain, wildcards)
    }

    /** Matches inverted rules (app exclusion lists), optionally filtered by important/regular. */
    private fun findInInvertedRules(
        rules: List<InvertedBlockRule>,
        domain: String,
        important: Boolean,
        packageName: String?
    ): BlockRuleMatch? {
        for (rule in rules) {
            if (rule.important == important && (packageName == null || packageName !in rule.excludedApps)) {
                if (rule.wildcard != null && rule.wildcard.matches(domain)) {
                    return BlockRuleMatch(rule.pattern, rule.source)
                } else if (rule.wildcard == null && matchesDomainOrSuffix(domain, rule.pattern)) {
                    return BlockRuleMatch(rule.pattern, rule.source)
                }
            }
        }
        return null
    }

    /** Exact match using the subscription mmap index first with the in-memory fallback, then a wildcard fallback. */
    private fun findSubscriptionTail(state: BlockRuleCacheState, domain: String, important: Boolean): BlockRuleMatch? {
        return if (important) {
            findSubscriptionExactMatch(state, domain, state.importantSubscriptionIndex, state.importantSubscriptionFallback)
                ?: findInWildcards(domain, state.importantSubscriptionWildcards)
        } else {
            findSubscriptionExactMatch(state, domain, state.subscriptionIndex, state.subscriptionFallback)
                ?: findInWildcards(domain, state.subscriptionWildcards)
        }
    }

    private fun findSubscriptionExactMatch(
        state: BlockRuleCacheState,
        domain: String,
        index: MappedSubscriptionRuleIndex?,
        subscriptions: Map<String, String>
    ): BlockRuleMatch? {
        index?.find(domain, state.subscriptionOverrides)?.let { source -> return BlockRuleMatch(domain, source) }
        fun sourceFor(pattern: String): String? = if (state.subscriptionOverrides.containsKey(pattern)) {
            state.subscriptionOverrides[pattern]
        } else {
            subscriptions[pattern]
        }
        return firstDomainSuffixHit(domain) { suffix ->
            sourceFor(suffix)?.let { source -> BlockRuleMatch(suffix, source) }
        }
    }

    private fun findInMap(domain: String, rules: Map<String, String>): BlockRuleMatch? =
        firstDomainSuffixHit(domain) { suffix ->
            rules[suffix]?.let { source -> BlockRuleMatch(pattern = suffix, source = source) }
        }

    private fun findInWildcards(
        domain: String,
        wildcards: List<Pair<AdGuardRuleParser.WildcardPattern, String>>
    ): BlockRuleMatch? =
        findWildcardHit(domain, wildcards) { it.first }?.let { (wp, source) -> BlockRuleMatch(wp.pattern, source) }

    private fun findInSpecialRules(
        rules: List<ExportedSpecialBlockRule>,
        domain: String,
        packageName: String?,
        important: Boolean,
        appSpecific: Boolean
    ): BlockRuleMatch? {
        for (rule in rules) {
            if (rule.important != important) continue
            val hasAppScope = !rule.appScope.isNullOrEmpty()
            if (appSpecific) {
                if (!hasAppScope || rule.appInverted) continue
            } else {
                if (hasAppScope && !rule.appInverted) continue
            }

            if (hasAppScope) {
                val pkgs = rule.appScope.split('|').map { it.trim().lowercase() }.filter { it.isNotEmpty() }.toSet()
                val pkg = packageName?.lowercase()
                if (rule.appInverted) {
                    if (pkg != null && pkgs.contains(pkg)) continue
                } else {
                    if (pkg == null || !pkgs.contains(pkg)) continue
                }
            }

            if (!rule.denyallow.isNullOrEmpty()) {
                val exceptions = rule.denyallow.split('|').map { it.trim().lowercase().trimEnd('.') }.filter { it.isNotEmpty() }
                if (exceptions.any { domain == it || domain.endsWith(".$it") }) {
                    continue
                }
            }

            val matched = if (rule.isRegex) {
                runCatching { Regex(rule.pattern).containsMatchIn(domain) }.getOrDefault(false)
            } else if (rule.isWildcard || rule.pattern.contains('*')) {
                AdGuardRuleParser.WildcardPattern(rule.pattern).matches(domain)
            } else {
                matchesDomainOrSuffix(domain, rule.pattern)
            }

            if (matched) {
                return BlockRuleMatch(rule.pattern, rule.source)
            }
        }
        return null
    }
}
