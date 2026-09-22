package com.haoze.diting.vpn

/**
 * Pure evaluation engine for allow rule matching.
 */
internal object AllowRuleMatcher {

    fun isAllowed(state: AllowRuleCacheState, qname: String, packageName: String? = null): Boolean {
        return findMatch(state, qname, packageName) != null
    }

    fun findMatch(state: AllowRuleCacheState, qname: String, packageName: String? = null): String? {
        return findImportantCustomMatch(state, qname, packageName)
            ?: findImportantSubscriptionMatch(state, qname, packageName)
            ?: findCustomMatch(state, qname, packageName)
            ?: findSubscriptionMatch(state, qname, packageName)
    }

    /**
     * Per-app allowlist rule matching (priority 3; covers both important and
     * regular allowlist rules).
     */
    fun findAppMatch(state: AllowRuleCacheState, qname: String, packageName: String): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty() || packageName.isEmpty()) return null

        findInAppBucket(state.customAppBuckets, packageName, domain, important = true)?.let { return it }
        findInAppBucket(state.customAppBuckets, packageName, domain, important = false)?.let { return it }
        findInAppBucket(state.subscriptionAppBuckets, packageName, domain, important = true)?.let { return it }
        findInAppBucket(state.subscriptionAppBuckets, packageName, domain, important = false)?.let { return it }
        findInSpecialRules(state.specialRules, domain, packageName, appSpecific = true)?.let { return it }

        return null
    }

    /**
     * Global allowlist rule matching (priority 4).
     */
    fun findGlobalMatch(state: AllowRuleCacheState, qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInInvertedRules(state.invertedCustomRules, domain, important = null, packageName)?.let { return it }

        findInSet(domain, state.importantCustomRules)?.let { return it }
        findInWildcards(domain, state.importantCustomWildcards)?.let { return it }
        findInSet(domain, state.customRules)?.let { return it }
        findInWildcards(domain, state.customWildcards)?.let { return it }

        findInInvertedRules(state.invertedSubscriptionRules, domain, important = null, packageName)?.let { return it }

        findInSpecialRules(state.specialRules, domain, packageName, appSpecific = false)?.let { return it }

        return findSubscriptionTail(state, domain, important = true)
            ?: findSubscriptionTail(state, domain, important = false)
    }

    fun findCustomMatch(state: AllowRuleCacheState, qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(state.customAppBuckets, packageName, domain, important = false)?.let { return it }

        findInInvertedRules(state.invertedCustomRules, domain, important = false, packageName)?.let { return it }

        return findInSet(domain, state.customRules) ?: findInWildcards(domain, state.customWildcards)
    }

    fun findImportantCustomMatch(state: AllowRuleCacheState, qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(state.customAppBuckets, packageName, domain, important = true)?.let { return it }

        findInInvertedRules(state.invertedCustomRules, domain, important = true, packageName)?.let { return it }

        return findInSet(domain, state.importantCustomRules) ?: findInWildcards(domain, state.importantCustomWildcards)
    }

    fun findSubscriptionMatch(state: AllowRuleCacheState, qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(state.subscriptionAppBuckets, packageName, domain, important = false)?.let { return it }

        findInInvertedRules(state.invertedSubscriptionRules, domain, important = false, packageName)?.let { return it }

        return findSubscriptionTail(state, domain, important = false)
    }

    fun findImportantSubscriptionMatch(state: AllowRuleCacheState, qname: String, packageName: String? = null): String? {
        val domain = qname.lowercase().trimEnd('.')
        if (domain.isEmpty()) return null

        findInAppBucket(state.subscriptionAppBuckets, packageName, domain, important = true)?.let { return it }

        findInInvertedRules(state.invertedSubscriptionRules, domain, important = true, packageName)?.let { return it }

        return findSubscriptionTail(state, domain, important = true)
    }

    /** Matches within the given app's rule bucket in exact-then-wildcard order. */
    private fun findInAppBucket(
        buckets: Map<String, AllowAppRuleBucket>,
        packageName: String?,
        domain: String,
        important: Boolean
    ): String? {
        val bucket = packageName?.let { buckets[it] } ?: return null
        val exact = if (important) bucket.importantExactRules else bucket.exactRules
        val wildcards = if (important) bucket.importantWildcardRules else bucket.wildcardRules
        return findInSet(domain, exact) ?: findInWildcards(domain, wildcards)
    }

    /** Matches inverted rules (app exclusion lists); a null [important] matches both important and regular rules. */
    private fun findInInvertedRules(
        rules: List<InvertedAllowRule>,
        domain: String,
        important: Boolean?,
        packageName: String?
    ): String? {
        for (rule in rules) {
            if ((important == null || rule.important == important) &&
                (packageName == null || packageName !in rule.excludedApps)
            ) {
                if (rule.wildcard != null && rule.wildcard.matches(domain)) {
                    return rule.pattern
                } else if (rule.wildcard == null && matchesDomainOrSuffix(domain, rule.pattern)) {
                    return rule.pattern
                }
            }
        }
        return null
    }

    /** Exact match using the subscription mmap index first with the in-memory fallback, then a wildcard fallback. */
    private fun findSubscriptionTail(state: AllowRuleCacheState, domain: String, important: Boolean): String? {
        return if (important) {
            findSubscriptionExactMatch(state, domain, state.importantSubscriptionIndex, state.importantSubscriptionFallback)
                ?: findInWildcards(domain, state.importantSubscriptionWildcards)
        } else {
            findSubscriptionExactMatch(state, domain, state.subscriptionIndex, state.subscriptionFallback)
                ?: findInWildcards(domain, state.subscriptionWildcards)
        }
    }

    private fun findSubscriptionExactMatch(
        state: AllowRuleCacheState,
        domain: String,
        index: MappedSubscriptionRuleIndex?,
        subscriptions: Set<String>
    ): String? {
        index?.find(domain, state.subscriptionOverrides)?.let { return it }
        fun isEnabled(pattern: String): Boolean = if (state.subscriptionOverrides.containsKey(pattern)) {
            state.subscriptionOverrides[pattern] != null
        } else {
            subscriptions.contains(pattern)
        }
        return firstDomainSuffixHit(domain) { suffix -> suffix.takeIf { isEnabled(it) } }
    }

    private fun findInSet(domain: String, rules: Set<String>): String? =
        firstDomainSuffixHit(domain) { suffix -> suffix.takeIf { it in rules } }

    private fun findInWildcards(domain: String, wildcards: List<AdGuardRuleParser.WildcardPattern>): String? =
        findWildcardHit(domain, wildcards) { it }?.pattern

    private fun findInSpecialRules(
        rules: List<ExportedSpecialAllowRule>,
        domain: String,
        packageName: String?,
        appSpecific: Boolean
    ): String? {
        for (rule in rules) {
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
                return rule.pattern
            }
        }
        return null
    }
}
