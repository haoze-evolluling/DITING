package com.haoze.diting.server.backend

import android.content.Context
import com.haoze.diting.data.DnsRulesDatabase
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.core.rule.RewriteAnswer
import com.haoze.diting.core.rule.RewriteRuleManager
import com.haoze.diting.core.rule.AllowListManager
import com.haoze.diting.core.rule.BlockListManager
import com.haoze.diting.core.rule.BlockResponseMode
import com.haoze.diting.core.rule.DomainDecision
import com.haoze.diting.core.rule.DomainPolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

/**
 * DNS mode query filter backed by the dedicated DNS mode rule database, so
 * its rules are fully isolated from the normal (VPN) mode's data. Decision
 * matrix: $important block > allow > regular block > default allow; hosts /
 * rewrite answers are exposed separately and are independent of the
 * filtering master switch.
 *
 * Deliberately runs without the mmap rule indexes (indexDirectory = null):
 * those files are owned by the VPN mode, so DNS mode keeps a pure in-memory
 * copy to avoid two modes writing the same index files.
 */
class DnsQueryFilter(context: Context) {

    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val loaded = AtomicBoolean(false)

    private val blockListManager = BlockListManager(
        DnsRulesDatabase.getInstance(appContext).blockRuleDao(),
        indexDirectory = null,
        scope = RuleScope.DNS,
        reloadCacheAfterChanges = false
    )

    private val allowListManager = AllowListManager(
        DnsRulesDatabase.getInstance(appContext).allowRuleDao(),
        indexDirectory = null,
        scope = RuleScope.DNS,
        reloadCacheAfterChanges = false
    )

    private val rewriteRuleManager = RewriteRuleManager(
        DnsRulesDatabase.getInstance(appContext).rewriteRuleDao(),
        indexDirectory = null,
        scope = RuleScope.DNS,
        reloadCacheAfterChanges = false
    )

    private val domainPolicy = DomainPolicy(allowListManager, blockListManager)

    @Volatile
    var blockResponseMode: BlockResponseMode = BlockResponseMode.NXDOMAIN
        private set

    /** Asynchronously (re)loads enabled rules and the block response mode. */
    fun reloadAsync() {
        scope.launch { reloadSync() }
    }

    suspend fun reloadSync() {
        blockListManager.refreshCache()
        allowListManager.refreshCache()
        rewriteRuleManager.refreshCache()
        blockResponseMode = DnsRuleSettings.blockResponseMode(appContext)
        domainPolicy.invalidateCache()
        loaded.set(true)
    }

    /** Rewrite (hosts) answers for one domain; empty when rules are not loaded yet. */
    fun rewriteAnswersFor(domain: String): Set<RewriteAnswer> =
        if (loaded.get()) rewriteRuleManager.answersFor(domain) else emptySet()

    fun isBlocked(domain: String): Boolean {
        if (!loaded.get()) return false
        return domainPolicy.evaluate(domain, packageName = null) is DomainDecision.Block
    }

    val policy: DomainPolicy get() = domainPolicy

    fun buildRuleSnapshotJson(): String = domainPolicy.buildRuleSnapshotJson(null)

    fun buildRewriteRulesJson(): String {
        val merged = org.json.JSONObject()
        rewriteRuleManager.ipRewrites().forEach { (domain, targets) ->
            merged.put(domain, org.json.JSONArray(targets))
        }
        rewriteRuleManager.cnameRedirects().forEach { (domain, target) ->
            if (!merged.has(domain)) merged.put(domain, target)
        }
        return merged.toString()
    }
}
