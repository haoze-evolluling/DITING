package com.haoze.diting.dnsmode.backend

import android.content.Context
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import com.haoze.diting.vpn.AllowListManager
import com.haoze.diting.vpn.BlockListManager
import com.haoze.diting.vpn.BlockResponseMode
import com.haoze.diting.vpn.DomainDecision
import com.haoze.diting.vpn.DomainPolicy
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

/**
 * DNS mode query filter backed by the same rule database the normal (VPN)
 * mode uses, so both modes share one rule set and one decision matrix
 * ($important block > allow > regular block > default allow).
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
        AppDatabase.getInstance(appContext).blockRuleDao(),
        indexDirectory = null,
        scope = RuleScope.DNS,
        reloadCacheAfterChanges = false
    )

    private val allowListManager = AllowListManager(
        AppDatabase.getInstance(appContext).allowRuleDao(),
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
        blockResponseMode = AppRulesSettingsStore.getBlockResponseMode(appContext)
        domainPolicy.invalidateCache()
        loaded.set(true)
    }

    fun isBlocked(domain: String): Boolean {
        if (!loaded.get()) return false
        return domainPolicy.evaluate(domain, packageName = null) is DomainDecision.Block
    }
}
