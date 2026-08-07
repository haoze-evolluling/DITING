package com.haoze.dnssr.vpn

sealed interface DomainDecision {
    val authority: String
    val matchedRule: String?

    data class Allow(
        override val authority: String,
        override val matchedRule: String? = null
    ) : DomainDecision

    data class Block(
        override val authority: String,
        override val matchedRule: String,
        val source: String
    ) : DomainDecision
}

class DomainPolicy(
    private val allowListManager: AllowListManager,
    private val blockListManager: BlockListManager
) {
    fun evaluate(authority: String): DomainDecision {
        blockListManager.findImportantCustomMatch(authority)?.let { match ->
            return DomainDecision.Block(authority, match.pattern, match.source)
        }
        blockListManager.findImportantSubscriptionMatch(authority)?.let { match ->
            return DomainDecision.Block(authority, match.pattern, match.source)
        }
        allowListManager.findCustomMatch(authority)?.let { rule ->
            return DomainDecision.Allow(authority, rule)
        }
        blockListManager.findCustomMatch(authority)?.let { match ->
            return DomainDecision.Block(authority, match.pattern, match.source)
        }
        allowListManager.findSubscriptionMatch(authority)?.let { rule ->
            return DomainDecision.Allow(authority, rule)
        }
        blockListManager.findSubscriptionMatch(authority)?.let { match ->
            return DomainDecision.Block(authority, match.pattern, match.source)
        }
        return DomainDecision.Allow(authority)
    }
}
