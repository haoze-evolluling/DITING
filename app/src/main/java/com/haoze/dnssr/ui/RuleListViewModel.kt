package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.data.entity.GoUrlRuleKind
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.BlockListManager
import com.haoze.dnssr.vpn.RewriteRuleManager
import com.haoze.dnssr.vpn.GoUrlRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class RuleListViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getInstance(application)
    private val blockRuleDao = db.blockRuleDao()
    private val allowRuleDao = db.allowRuleDao()
    private val subscriptionDao = db.subscriptionDao()
    private val rewriteRuleDao = db.rewriteRuleDao()
    private val goUrlRuleDao = db.goUrlRuleDao()

    private val pageSize = 100

    private val _rules = MutableStateFlow<List<RuleListItem>>(emptyList())
    val rules: StateFlow<List<RuleListItem>> = _rules.asStateFlow()

    private val _currentPage = MutableStateFlow(1)
    val currentPage: StateFlow<Int> = _currentPage.asStateFlow()

    private val _totalPages = MutableStateFlow(1)
    val totalPages: StateFlow<Int> = _totalPages.asStateFlow()

    private val _totalCount = MutableStateFlow(0)
    val totalCount: StateFlow<Int> = _totalCount.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _sourceFilter = MutableStateFlow<RuleSourceFilter>(RuleSourceFilter.All)
    val sourceFilter: StateFlow<RuleSourceFilter> = _sourceFilter.asStateFlow()

    private val _sourceSubscriptions = MutableStateFlow<List<SubscriptionEntity>>(emptyList())
    val sourceSubscriptions: StateFlow<List<SubscriptionEntity>> = _sourceSubscriptions.asStateFlow()

    private var activated = false
    private var ruleKind = ManagedRuleKind.BLOCK
    private var ruleScope = RuleScope.DNS

    fun setRuleKind(kind: ManagedRuleKind, scope: RuleScope) {
        if (ruleKind == kind && ruleScope == scope) return
        ruleKind = kind
        ruleScope = scope
        _searchQuery.value = ""
        _sourceFilter.value = RuleSourceFilter.All
        if (activated) {
            loadSourceSubscriptions()
            loadPage(1)
        }
    }

    fun activate() {
        if (!activated) {
            activated = true
        }
        loadSourceSubscriptions()
        loadPage(1)
    }

    fun loadPage(page: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val query = _searchQuery.value.trim()
            val offset = (page - 1) * pageSize
            val rules = loadRules(query, pageSize, offset)
            val total = countRules(query)
            val pages = if (total == 0) 1 else (total + pageSize - 1) / pageSize
            withContext(Dispatchers.Main) {
                _rules.value = rules
                _currentPage.value = page.coerceAtMost(pages)
                _totalPages.value = pages
                _totalCount.value = total
            }
        }
    }

    fun onSearchQueryChange(query: String) {
        _searchQuery.value = query
        loadPage(1)
    }

    fun selectSourceFilter(filter: RuleSourceFilter) {
        if (_sourceFilter.value == filter) return
        _sourceFilter.value = filter
        loadPage(1)
    }

    fun deleteRule(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val rewriteRuleManager = RewriteRuleManager(rewriteRuleDao, java.io.File(context.filesDir, "rule-index"), ruleScope)
            val allowListManager = AllowListManager(allowRuleDao, scope = ruleScope)
            val blockListManager = BlockListManager(blockRuleDao, scope = ruleScope)
            if (ruleKind.isUrlRule) {
                GoUrlRuleManager(goUrlRuleDao).delete(id)
                RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            } else if (ruleKind == ManagedRuleKind.REWRITE) {
                rewriteRuleManager.deleteRule(id)
                refreshRewriteRules(context)
            } else if (ruleKind == ManagedRuleKind.ALLOW) {
                val rebuildSubscriptionIndex = allowRuleDao.hasSubscriptionSource(id)
                allowListManager.deleteRule(id)?.let {
                    if (rebuildSubscriptionIndex) {
                        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(context, false, true, false, ruleScope)
                    } else {
                        RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "allow", it, ruleScope)
                    }
                }
            } else {
                val rebuildSubscriptionIndex = blockRuleDao.hasSubscriptionSource(id)
                blockListManager.deleteRule(id)?.let {
                    if (rebuildSubscriptionIndex) {
                        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(context, true, false, false, ruleScope)
                    } else {
                        RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "block", it, ruleScope)
                    }
                }
            }
            loadPage(_currentPage.value)
        }
    }

    fun toggleRule(id: Long, enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val rewriteRuleManager = RewriteRuleManager(rewriteRuleDao, java.io.File(context.filesDir, "rule-index"), ruleScope)
            val allowListManager = AllowListManager(allowRuleDao, scope = ruleScope)
            val blockListManager = BlockListManager(blockRuleDao, scope = ruleScope)
            if (ruleKind.isUrlRule) {
                GoUrlRuleManager(goUrlRuleDao).setEnabled(id, enabled)
                RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            } else if (ruleKind == ManagedRuleKind.REWRITE) {
                rewriteRuleManager.toggleRule(id, enabled)
                refreshRewriteRules(context)
            } else if (ruleKind == ManagedRuleKind.ALLOW) {
                val rebuildSubscriptionIndex = allowRuleDao.hasSubscriptionSource(id)
                allowListManager.toggleRule(id, enabled)?.let {
                    if (rebuildSubscriptionIndex) {
                        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(context, false, true, false, ruleScope)
                    } else {
                        RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "allow", it, ruleScope)
                    }
                }
            } else {
                val rebuildSubscriptionIndex = blockRuleDao.hasSubscriptionSource(id)
                blockListManager.toggleRule(id, enabled)?.let {
                    if (rebuildSubscriptionIndex) {
                        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(context, true, false, false, ruleScope)
                    } else {
                        RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "block", it, ruleScope)
                    }
                }
            }
            loadPage(_currentPage.value)
        }
    }

    private fun refreshRewriteRules(context: Application) {
        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(context, false, false, true, ruleScope)
    }

    private suspend fun loadRules(query: String, limit: Int, offset: Int): List<RuleListItem> {
        val source = _sourceFilter.value.source
        return if (ruleKind.isUrlRule) {
            val rules = goUrlRuleDao.byKind(ruleKind.goUrlRuleKind!!)
                .filter { query.isEmpty() || it.pattern.contains(query, ignoreCase = true) || it.rawLine.contains(query, ignoreCase = true) }
                .drop(offset)
                .take(limit)
            rules.map { RuleListItem(it.id, it.pattern, it.rawLine, it.enabled) }
        } else if (ruleKind == ManagedRuleKind.REWRITE) {
            val rules = if (source == null) {
                if (query.isEmpty()) rewriteRuleDao.paged(ruleScope.storageValue, limit, offset) else rewriteRuleDao.searchPaged(ruleScope.storageValue, "%$query%", limit, offset)
            } else {
                if (query.isEmpty()) rewriteRuleDao.pagedBySource(source, limit, offset) else rewriteRuleDao.searchPagedBySource(source, "%$query%", limit, offset)
            }
            rules.map { RuleListItem(it.id, it.pattern, "${it.pattern} -> ${it.targetValue}", it.enabled, it.targetType) }
        } else if (ruleKind == ManagedRuleKind.ALLOW) {
            val rules = if (source == null) {
                if (query.isEmpty()) allowRuleDao.paged(ruleScope.storageValue, limit, offset)
                else allowRuleDao.searchPaged(ruleScope.storageValue, "%$query%", limit, offset)
            } else {
                if (query.isEmpty()) allowRuleDao.pagedBySource(source, limit, offset)
                else allowRuleDao.searchPagedBySource(source, "%$query%", limit, offset)
            }
            rules.map { RuleListItem(it.id, it.pattern, it.rawLine, it.enabled) }
        } else {
            val rules = if (source == null) {
                if (query.isEmpty()) blockRuleDao.paged(ruleScope.storageValue, limit, offset)
                else blockRuleDao.searchPaged(ruleScope.storageValue, "%$query%", limit, offset)
            } else {
                if (query.isEmpty()) blockRuleDao.pagedBySource(source, limit, offset)
                else blockRuleDao.searchPagedBySource(source, "%$query%", limit, offset)
            }
            rules.map { RuleListItem(it.id, it.pattern, it.rawLine, it.enabled) }
        }
    }

    private suspend fun countRules(query: String): Int {
        val source = _sourceFilter.value.source
        return if (ruleKind.isUrlRule) {
            goUrlRuleDao.byKind(ruleKind.goUrlRuleKind!!)
                .count { query.isEmpty() || it.pattern.contains(query, ignoreCase = true) || it.rawLine.contains(query, ignoreCase = true) }
        } else if (ruleKind == ManagedRuleKind.REWRITE) {
            if (source == null) { if (query.isEmpty()) rewriteRuleDao.count(ruleScope.storageValue) else rewriteRuleDao.searchCount(ruleScope.storageValue, "%$query%") }
            else { if (query.isEmpty()) rewriteRuleDao.countBySourceForList(source) else rewriteRuleDao.searchCountBySource(source, "%$query%") }
        } else if (ruleKind == ManagedRuleKind.ALLOW) {
            if (source == null) {
                if (query.isEmpty()) allowRuleDao.count(ruleScope.storageValue) else allowRuleDao.searchCount(ruleScope.storageValue, "%$query%")
            } else {
                if (query.isEmpty()) allowRuleDao.countBySourceForList(source)
                else allowRuleDao.searchCountBySource(source, "%$query%")
            }
        } else {
            if (source == null) {
                if (query.isEmpty()) blockRuleDao.count(ruleScope.storageValue) else blockRuleDao.searchCount(ruleScope.storageValue, "%$query%")
            } else {
                if (query.isEmpty()) blockRuleDao.countBySourceForList(source)
                else blockRuleDao.searchCountBySource(source, "%$query%")
            }
        }
    }

    private fun loadSourceSubscriptions() {
        viewModelScope.launch(Dispatchers.IO) {
            val subscriptions = if (ruleKind.isUrlRule) {
                emptyList()
            } else if (ruleKind == ManagedRuleKind.REWRITE) {
                subscriptionDao.allByKind(com.haoze.dnssr.data.entity.SubscriptionKind.REWRITE)
            } else if (ruleKind == ManagedRuleKind.ALLOW) {
                subscriptionDao.withAllowRules()
            } else {
                subscriptionDao.withBlockRules()
            }
            withContext(Dispatchers.Main) {
                _sourceSubscriptions.value = subscriptions
            }
        }
    }
}

sealed interface RuleSourceFilter {
    val source: String?

    data object All : RuleSourceFilter {
        override val source: String? = null
    }

    data object Manual : RuleSourceFilter {
        override val source = "useradd"
    }

    data class Subscription(val id: Long) : RuleSourceFilter {
        override val source = "sub_$id"
    }
}

enum class ManagedRuleKind(
    val title: String,
    val countLabel: String,
    val goUrlRuleKind: String? = null
) {
    BLOCK("屏蔽规则", "屏蔽规则"),
    ALLOW("放行规则", "白名单规则"),
    REWRITE("覆写域名规则", "覆写规则"),
    URL_BLOCK("URL 屏蔽规则", "URL 屏蔽规则", GoUrlRuleKind.BLOCK),
    URL_ALLOW("URL 放行规则", "URL 放行规则", GoUrlRuleKind.ALLOW);

    val isUrlRule: Boolean get() = goUrlRuleKind != null
}

data class RuleListItem(
    val id: Long,
    val pattern: String,
    val rawLine: String,
    val enabled: Boolean,
    val targetType: String? = null
)
