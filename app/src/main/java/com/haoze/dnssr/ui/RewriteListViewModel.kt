package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.RewriteRuleEntity
import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.RewriteRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

enum class RewriteListFilter(val labelResName: String) {
    ALL("全部"),
    USER_ADDED("用户自定义"),
    SUBSCRIPTION("规则订阅"),
    IPV4("IPv4"),
    IPV6("IPv6"),
    CNAME("CNAME")
}

data class RewriteListItem(
    val id: Long,
    val pattern: String,
    val targetType: String,
    val targetValue: String,
    val rawLine: String,
    val enabled: Boolean,
    val masterEnabled: Boolean = true,
    val effectiveEnabled: Boolean = enabled && masterEnabled,
    val addedAt: Long,
    val isUserRule: Boolean = true,
    val isSubscription: Boolean = false,
    val subscriptionName: String? = null
)

data class RewriteListStats(
    val totalActive: Int = 0,
    val totalRules: Int = 0,
    val ipv4Count: Int = 0,
    val ipv6Count: Int = 0,
    val cnameCount: Int = 0,
    val userTotal: Int = 0,
    val userEnabled: Int = 0,
    val subscriptionCount: Int = 0
)

class RewriteListViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getInstance(application)
    private val rewriteRuleDao = db.rewriteRuleDao()
    private val subscriptionDao = db.subscriptionDao()
    private val rewriteRuleManager = RewriteRuleManager(
        rewriteRuleDao,
        File(application.filesDir, "rule-index"),
        RuleScope.DNS
    )

    private val pageSize = 100

    private val _stats = MutableStateFlow(RewriteListStats())
    val stats: StateFlow<RewriteListStats> = _stats.asStateFlow()

    private val _items = MutableStateFlow<List<RewriteListItem>>(emptyList())
    val items: StateFlow<List<RewriteListItem>> = _items.asStateFlow()

    private val _currentPage = MutableStateFlow(1)
    val currentPage: StateFlow<Int> = _currentPage.asStateFlow()

    private val _totalPages = MutableStateFlow(1)
    val totalPages: StateFlow<Int> = _totalPages.asStateFlow()

    private val _totalCount = MutableStateFlow(0)
    val totalCount: StateFlow<Int> = _totalCount.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _filter = MutableStateFlow(RewriteListFilter.ALL)
    val filter: StateFlow<RewriteListFilter> = _filter.asStateFlow()

    private var activated = false

    fun activate() {
        if (!activated) {
            activated = true
            refreshAll()
        } else {
            refreshAll()
        }
    }

    fun setFilter(newFilter: RewriteListFilter) {
        if (_filter.value == newFilter) return
        _filter.value = newFilter
        loadPage(1)
    }

    fun setSearchQuery(query: String) {
        _searchQuery.value = query
        loadPage(1)
    }

    fun refreshAll() {
        loadStats()
        loadPage(_currentPage.value)
    }

    fun loadStats() {
        viewModelScope.launch(Dispatchers.IO) {
            val domainRulesEnabled = AppSettings.isDomainRulesEnabled(getApplication())
            val addressRulesOperational = AppSettings.isAddressRulesFullyOperational(getApplication())

            val ipv4Total = rewriteRuleDao.countByTargetType(RewriteTargetType.IPV4)
            val ipv6Total = rewriteRuleDao.countByTargetType(RewriteTargetType.IPV6)
            val cnameTotal = rewriteRuleDao.countByTargetType(RewriteTargetType.CNAME)

            val ipv4Enabled = if (domainRulesEnabled) rewriteRuleDao.enabledCountByTargetType(RewriteTargetType.IPV4) else 0
            val ipv6Enabled = if (domainRulesEnabled) rewriteRuleDao.enabledCountByTargetType(RewriteTargetType.IPV6) else 0
            val cnameEnabled = if (addressRulesOperational) rewriteRuleDao.enabledCountByTargetType(RewriteTargetType.CNAME) else 0

            val totalActive = ipv4Enabled + ipv6Enabled + cnameEnabled
            val totalRules = rewriteRuleDao.count()
            val userTotal = rewriteRuleDao.userRulesCount()
            val userEnabled = rewriteRuleDao.enabledUserRulesCount()
            val subscriptionCount = rewriteRuleDao.subscriptionRulesCount()

            _stats.value = RewriteListStats(
                totalActive = totalActive,
                totalRules = totalRules,
                ipv4Count = ipv4Total,
                ipv6Count = ipv6Total,
                cnameCount = cnameTotal,
                userTotal = userTotal,
                userEnabled = userEnabled,
                subscriptionCount = subscriptionCount
            )
        }
    }

    fun loadPage(page: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val query = _searchQuery.value.trim()
            val currentFilter = _filter.value
            val domainRulesEnabled = AppSettings.isDomainRulesEnabled(getApplication())
            val addressRulesOperational = AppSettings.isAddressRulesFullyOperational(getApplication())

            val total = when (currentFilter) {
                RewriteListFilter.ALL -> {
                    if (query.isEmpty()) rewriteRuleDao.count() else rewriteRuleDao.searchCount("%$query%")
                }
                RewriteListFilter.USER_ADDED -> {
                    if (query.isEmpty()) rewriteRuleDao.userRulesCount() else rewriteRuleDao.searchUserRulesCount("%$query%")
                }
                RewriteListFilter.SUBSCRIPTION -> {
                    if (query.isEmpty()) rewriteRuleDao.subscriptionRulesCount() else rewriteRuleDao.searchSubscriptionRulesCount("%$query%")
                }
                RewriteListFilter.IPV4 -> {
                    if (query.isEmpty()) rewriteRuleDao.countByTargetType(RewriteTargetType.IPV4)
                    else rewriteRuleDao.searchCountByTargetType(RewriteTargetType.IPV4, "%$query%")
                }
                RewriteListFilter.IPV6 -> {
                    if (query.isEmpty()) rewriteRuleDao.countByTargetType(RewriteTargetType.IPV6)
                    else rewriteRuleDao.searchCountByTargetType(RewriteTargetType.IPV6, "%$query%")
                }
                RewriteListFilter.CNAME -> {
                    if (query.isEmpty()) rewriteRuleDao.countByTargetType(RewriteTargetType.CNAME)
                    else rewriteRuleDao.searchCountByTargetType(RewriteTargetType.CNAME, "%$query%")
                }
            }

            val pages = if (total == 0) 1 else (total + pageSize - 1) / pageSize
            val safePage = page.coerceIn(1, pages)
            val offset = (safePage - 1) * pageSize

            val entities: List<RewriteRuleEntity> = when (currentFilter) {
                RewriteListFilter.ALL -> {
                    if (query.isEmpty()) rewriteRuleDao.paged(pageSize, offset)
                    else rewriteRuleDao.searchPaged("%$query%", pageSize, offset)
                }
                RewriteListFilter.USER_ADDED -> {
                    if (query.isEmpty()) rewriteRuleDao.userRulesPaged(pageSize, offset)
                    else rewriteRuleDao.searchUserRulesPaged("%$query%", pageSize, offset)
                }
                RewriteListFilter.SUBSCRIPTION -> {
                    if (query.isEmpty()) rewriteRuleDao.subscriptionRulesPaged(pageSize, offset)
                    else rewriteRuleDao.searchSubscriptionRulesPaged("%$query%", pageSize, offset)
                }
                RewriteListFilter.IPV4 -> {
                    if (query.isEmpty()) rewriteRuleDao.pagedByTargetType(RewriteTargetType.IPV4, pageSize, offset)
                    else rewriteRuleDao.searchPagedByTargetType(RewriteTargetType.IPV4, "%$query%", pageSize, offset)
                }
                RewriteListFilter.IPV6 -> {
                    if (query.isEmpty()) rewriteRuleDao.pagedByTargetType(RewriteTargetType.IPV6, pageSize, offset)
                    else rewriteRuleDao.searchPagedByTargetType(RewriteTargetType.IPV6, "%$query%", pageSize, offset)
                }
                RewriteListFilter.CNAME -> {
                    if (query.isEmpty()) rewriteRuleDao.pagedByTargetType(RewriteTargetType.CNAME, pageSize, offset)
                    else rewriteRuleDao.searchPagedByTargetType(RewriteTargetType.CNAME, "%$query%", pageSize, offset)
                }
            }

            val ruleIds = entities.map { it.id }
            val sources = if (ruleIds.isNotEmpty()) rewriteRuleDao.sourcesForRuleIds(ruleIds) else emptyList()
            val subscriptions = subscriptionDao.all().associateBy { "sub_${it.id}" }

            val ruleSourceMap = sources.groupBy { it.ruleId }

            val items = entities.map { entity ->
                val entitySources = ruleSourceMap[entity.id].orEmpty()
                val isUser = entitySources.any { !it.source.startsWith("sub_") } || entitySources.isEmpty()
                val subSource = entitySources.firstOrNull { it.source.startsWith("sub_") }
                val isSub = subSource != null
                val subName = subSource?.let { subscriptions[it.source]?.name }
                val isDomainType = entity.targetType == RewriteTargetType.IPV4 || entity.targetType == RewriteTargetType.IPV6
                val masterEnabled = if (isDomainType) domainRulesEnabled else addressRulesOperational

                RewriteListItem(
                    id = entity.id,
                    pattern = entity.pattern,
                    targetType = entity.targetType,
                    targetValue = entity.targetValue,
                    rawLine = entity.rawLine,
                    enabled = entity.enabled,
                    masterEnabled = masterEnabled,
                    effectiveEnabled = entity.enabled && masterEnabled,
                    addedAt = entity.addedAt,
                    isUserRule = isUser,
                    isSubscription = isSub,
                    subscriptionName = subName
                )
            }

            withContext(Dispatchers.Main) {
                _items.value = items
                _currentPage.value = safePage
                _totalPages.value = pages
                _totalCount.value = total
            }
        }
    }

    suspend fun addRule(
        domain: String,
        targetType: String,
        targetValue: String
    ): Result<String> = withContext(Dispatchers.IO) {
        val trimmedDomain = domain.trim()
        val trimmedValue = targetValue.trim()
        if (trimmedDomain.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("域名不能为空"))
        }
        if (trimmedValue.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("目标地址不能为空"))
        }

        val success = rewriteRuleManager.addRule(trimmedDomain, targetType, trimmedValue)
        if (success) {
            val context = getApplication<Application>()
            RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                context, refreshBlock = false, refreshAllow = false, refreshRewrite = true, RuleScope.DNS
            )
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            loadStats()
            loadPage(1)
            Result.success("已添加覆写规则")
        } else {
            Result.failure(IllegalArgumentException("域名、目标格式无效或存在规则冲突"))
        }
    }

    suspend fun editRule(
        item: RewriteListItem,
        newPattern: String,
        newTargetType: String,
        newTargetValue: String
    ): Result<String> = withContext(Dispatchers.IO) {
        val trimmedDomain = newPattern.trim()
        val trimmedValue = newTargetValue.trim()
        if (trimmedDomain.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("域名不能为空"))
        }
        if (trimmedValue.isEmpty()) {
            return@withContext Result.failure(IllegalArgumentException("目标地址不能为空"))
        }

        val success = rewriteRuleManager.editRule(item.id, trimmedDomain, newTargetType, trimmedValue)
        if (success) {
            val context = getApplication<Application>()
            RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                context, refreshBlock = false, refreshAllow = false, refreshRewrite = true, RuleScope.DNS
            )
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            loadStats()
            loadPage(_currentPage.value)
            Result.success("已保存修改")
        } else {
            Result.failure(IllegalArgumentException("修改失败：格式无效或存在规则冲突"))
        }
    }

    fun deleteRule(item: RewriteListItem) {
        viewModelScope.launch(Dispatchers.IO) {
            rewriteRuleManager.deleteRule(item.id)
            val context = getApplication<Application>()
            RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                context, refreshBlock = false, refreshAllow = false, refreshRewrite = true, RuleScope.DNS
            )
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            loadStats()
            loadPage(_currentPage.value)
        }
    }

    fun toggleRule(item: RewriteListItem, enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            rewriteRuleManager.toggleRule(item.id, enabled)
            val context = getApplication<Application>()
            RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                context, refreshBlock = false, refreshAllow = false, refreshRewrite = true, RuleScope.DNS
            )
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            loadStats()
            loadPage(_currentPage.value)
        }
    }

    fun clearUserRules() {
        viewModelScope.launch(Dispatchers.IO) {
            rewriteRuleManager.clearUserRules()
            val context = getApplication<Application>()
            RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                context, refreshBlock = false, refreshAllow = false, refreshRewrite = true, RuleScope.DNS
            )
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
            loadStats()
            loadPage(1)
        }
    }
}
