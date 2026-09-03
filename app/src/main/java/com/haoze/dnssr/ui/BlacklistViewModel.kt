package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.BlockRuleEntity
import com.haoze.dnssr.data.entity.GoUrlRuleEntity
import com.haoze.dnssr.data.entity.GoUrlRuleKind
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.AdGuardRuleParser
import com.haoze.dnssr.vpn.BlockListManager
import com.haoze.dnssr.vpn.GoUrlRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class BlacklistType {
    DOMAIN,
    URL
}

enum class BlacklistFilter(val labelResName: String) {
    ALL("全部"),
    USER_ADDED("用户自定义"),
    SUBSCRIPTION("规则订阅"),
    DOMAIN("域名屏蔽"),
    URL("URL 屏蔽")
}

data class BlacklistItem(
    val id: Long,
    val pattern: String,
    val rawLine: String,
    val type: BlacklistType,
    val groupName: String?,
    val appScope: String?,
    val appInverted: Boolean,
    val isWildcard: Boolean,
    val important: Boolean,
    val enabled: Boolean,
    val masterEnabled: Boolean = true,
    val effectiveEnabled: Boolean = enabled && masterEnabled,
    val addedAt: Long,
    val isUserRule: Boolean = true,
    val isSubscription: Boolean = false,
    val subscriptionName: String? = null
)

data class BlacklistStats(
    val totalDomains: Int = 0,
    val userTotal: Int = 0,
    val userEnabled: Int = 0,
    val urlBlockCount: Int = 0,
    val totalActive: Int = 0
)

class BlacklistViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getInstance(application)
    private val blockRuleDao = db.blockRuleDao()
    private val goUrlRuleDao = db.goUrlRuleDao()
    private val subscriptionDao = db.subscriptionDao()
    private val blockListManager = BlockListManager(blockRuleDao, scope = RuleScope.DNS)
    private val goUrlRuleManager = GoUrlRuleManager(goUrlRuleDao)

    private val pageSize = 100

    private val _stats = MutableStateFlow(BlacklistStats())
    val stats: StateFlow<BlacklistStats> = _stats.asStateFlow()

    private val _items = MutableStateFlow<List<BlacklistItem>>(emptyList())
    val items: StateFlow<List<BlacklistItem>> = _items.asStateFlow()

    private val _currentPage = MutableStateFlow(1)
    val currentPage: StateFlow<Int> = _currentPage.asStateFlow()

    private val _totalPages = MutableStateFlow(1)
    val totalPages: StateFlow<Int> = _totalPages.asStateFlow()

    private val _totalCount = MutableStateFlow(0)
    val totalCount: StateFlow<Int> = _totalCount.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _filter = MutableStateFlow(BlacklistFilter.ALL)
    val filter: StateFlow<BlacklistFilter> = _filter.asStateFlow()

    private var activated = false

    fun activate() {
        if (!activated) {
            activated = true
            refreshAll()
        } else {
            refreshAll()
        }
    }

    fun setFilter(newFilter: BlacklistFilter) {
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

            val totalDomains = if (domainRulesEnabled) blockRuleDao.enabledPatternsCount() else 0
            val userTotal = blockRuleDao.userRulesCount()
            val userEnabled = if (domainRulesEnabled) blockRuleDao.enabledUserRulesCount() else 0
            val urlBlockCount = goUrlRuleDao.count(GoUrlRuleKind.BLOCK)
            val urlEnabled = if (addressRulesOperational) goUrlRuleDao.enabledCount(GoUrlRuleKind.BLOCK) else 0
            val totalActive = totalDomains + urlEnabled

            _stats.value = BlacklistStats(
                totalDomains = totalDomains,
                userTotal = userTotal,
                userEnabled = userEnabled,
                urlBlockCount = urlBlockCount,
                totalActive = totalActive
            )
        }
    }

    fun loadPage(page: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val query = _searchQuery.value.trim()
            val currentFilter = _filter.value
            val domainRulesEnabled = AppSettings.isDomainRulesEnabled(getApplication())
            val addressRulesOperational = AppSettings.isAddressRulesFullyOperational(getApplication())

            // 1. 获取适用的 URL 屏蔽规则（URL 规则条目较少，在内存中过滤）
            val allUrlEntities = when (currentFilter) {
                BlacklistFilter.ALL, BlacklistFilter.USER_ADDED, BlacklistFilter.URL -> {
                    goUrlRuleDao.byKind(GoUrlRuleKind.BLOCK)
                }
                else -> emptyList()
            }

            val filteredUrls = allUrlEntities.filter { item ->
                if (query.isEmpty()) true
                else item.pattern.contains(query, ignoreCase = true) || item.rawLine.contains(query, ignoreCase = true)
            }
            val urlCount = filteredUrls.size

            // 2. 根据筛选和搜索词计算域名屏蔽规则数量
            val domainCount = when (currentFilter) {
                BlacklistFilter.ALL, BlacklistFilter.DOMAIN -> {
                    if (query.isEmpty()) blockRuleDao.count() else blockRuleDao.searchCount("%$query%")
                }
                BlacklistFilter.USER_ADDED -> {
                    if (query.isEmpty()) blockRuleDao.userRulesCount() else blockRuleDao.searchUserRulesCount("%$query%")
                }
                BlacklistFilter.SUBSCRIPTION -> {
                    if (query.isEmpty()) blockRuleDao.subscriptionRulesCount() else blockRuleDao.searchSubscriptionRulesCount("%$query%")
                }
                BlacklistFilter.URL -> 0
            }

            val total = urlCount + domainCount
            val pages = if (total == 0) 1 else (total + pageSize - 1) / pageSize
            val safePage = page.coerceIn(1, pages)
            val offset = (safePage - 1) * pageSize

            // 3. 分页切片并从 SQLite 查询当前页域名规则
            val pagedUrlEntities: List<GoUrlRuleEntity>
            val pagedDomainEntities: List<BlockRuleEntity>

            if (currentFilter == BlacklistFilter.URL) {
                pagedUrlEntities = filteredUrls.drop(offset).take(pageSize)
                pagedDomainEntities = emptyList()
            } else if (currentFilter == BlacklistFilter.SUBSCRIPTION || currentFilter == BlacklistFilter.DOMAIN) {
                pagedUrlEntities = emptyList()
                pagedDomainEntities = queryDomainEntities(currentFilter, query, pageSize, offset)
            } else {
                // ALL 或 USER_ADDED：URL 规则优先显示，其后为域名规则
                if (offset < urlCount) {
                    pagedUrlEntities = filteredUrls.drop(offset).take(pageSize)
                    val domainLimit = pageSize - pagedUrlEntities.size
                    pagedDomainEntities = if (domainLimit > 0) {
                        queryDomainEntities(currentFilter, query, domainLimit, 0)
                    } else emptyList()
                } else {
                    pagedUrlEntities = emptyList()
                    val domainOffset = offset - urlCount
                    pagedDomainEntities = queryDomainEntities(currentFilter, query, pageSize, domainOffset)
                }
            }

            // 4. 批量查询来源及订阅名称，精准展示来源徽标
            val domainRuleIds = pagedDomainEntities.map { it.id }
            val domainSources = if (domainRuleIds.isNotEmpty()) blockRuleDao.sourcesForRuleIds(domainRuleIds) else emptyList()
            val domainSourcesByRuleId = domainSources.groupBy { it.ruleId }

            val urlRuleIds = pagedUrlEntities.map { it.id }
            val urlSources = if (urlRuleIds.isNotEmpty()) goUrlRuleDao.sourcesForRuleIds(urlRuleIds) else emptyList()
            val urlSourcesByRuleId = urlSources.groupBy { it.ruleId }

            val subscriptionsMap = subscriptionDao.all().associateBy { "sub_${it.id}" }

            val domainItems = pagedDomainEntities.map { entity ->
                val sources = domainSourcesByRuleId[entity.id].orEmpty()
                val isUser = sources.any { it.source == "useradd" || !it.source.startsWith("sub_") }
                val subSources = sources.filter { it.source.startsWith("sub_") }
                val isSub = subSources.isNotEmpty()
                val subName = subSources.firstOrNull()?.let { subscriptionsMap[it.source]?.name }
                entity.toItem(
                    isUserRule = isUser,
                    isSubscription = isSub,
                    subscriptionName = subName,
                    masterEnabled = domainRulesEnabled
                )
            }

            val urlItems = pagedUrlEntities.map { entity ->
                val sources = urlSourcesByRuleId[entity.id].orEmpty()
                val isUser = sources.isEmpty() || sources.any { it.source == GoUrlRuleManager.USER_SOURCE || !it.source.startsWith("sub_") }
                val isSub = sources.any { it.source.startsWith("sub_") }
                val subName = sources.firstOrNull { it.source.startsWith("sub_") }?.let { subscriptionsMap[it.source]?.name }
                entity.toItem(
                    isUserRule = isUser,
                    isSubscription = isSub,
                    subscriptionName = subName,
                    masterEnabled = addressRulesOperational
                )
            }

            val combined = urlItems + domainItems

            withContext(Dispatchers.Main) {
                _items.value = combined
                _currentPage.value = safePage
                _totalPages.value = pages
                _totalCount.value = total
            }
        }
    }

    private suspend fun queryDomainEntities(
        filter: BlacklistFilter,
        query: String,
        limit: Int,
        offset: Int
    ): List<BlockRuleEntity> = when (filter) {
        BlacklistFilter.USER_ADDED -> {
            if (query.isEmpty()) blockRuleDao.userRulesPaged(limit, offset)
            else blockRuleDao.searchUserRulesPaged("%$query%", limit, offset)
        }
        BlacklistFilter.SUBSCRIPTION -> {
            if (query.isEmpty()) blockRuleDao.subscriptionRulesPaged(limit, offset)
            else blockRuleDao.searchSubscriptionRulesPaged("%$query%", limit, offset)
        }
        else -> {
            if (query.isEmpty()) blockRuleDao.paged(limit, offset)
            else blockRuleDao.searchPaged("%$query%", limit, offset)
        }
    }

    fun toggleRule(item: BlacklistItem, enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            if (item.type == BlacklistType.DOMAIN) {
                blockListManager.toggleRule(item.id, enabled)?.let {
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                        getApplication(),
                        "block",
                        it,
                        RuleScope.DNS
                    )
                }
            } else {
                goUrlRuleManager.setEnabled(item.id, enabled)
                syncUrlRules()
            }
            refreshAll()
        }
    }

    fun deleteRule(item: BlacklistItem) {
        viewModelScope.launch(Dispatchers.IO) {
            if (item.type == BlacklistType.DOMAIN) {
                blockListManager.deleteRule(item.id)?.let {
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                        getApplication(),
                        "block",
                        it,
                        RuleScope.DNS
                    )
                }
            } else {
                goUrlRuleManager.delete(item.id)
                syncUrlRules()
            }
            refreshAll()
        }
    }

    suspend fun addRule(
        input: String,
        appScope: String? = null,
        appInverted: Boolean = false,
        important: Boolean = false
    ): Result<String> = withContext(Dispatchers.IO) {
        val raw = input.trim()
        if (raw.isEmpty()) return@withContext Result.failure(IllegalArgumentException("规则内容不能为空"))

        // Check if URL block rule
        val isHttpUrl = raw.startsWith("http://", ignoreCase = true) ||
                raw.startsWith("https://", ignoreCase = true) ||
                raw.startsWith("||http://", ignoreCase = true) ||
                raw.startsWith("||https://", ignoreCase = true)

        if (isHttpUrl) {
            val line = if (raw.startsWith("||")) raw.removePrefix("||") else raw
            val success = goUrlRuleManager.addRule(line)
            if (success) {
                syncUrlRules()
                refreshAll()
                return@withContext Result.success("已添加 URL 屏蔽规则")
            } else {
                return@withContext Result.failure(IllegalArgumentException("URL 格式无效或规则已存在"))
            }
        }

        // Domain block rule
        val normalizedLine = when {
            raw.startsWith("||") -> raw
            raw.startsWith("0.0.0.0 ") || raw.startsWith("127.0.0.1 ") -> raw
            else -> "||$raw^"
        }

        val parsed = AdGuardRuleParser.parseLine(normalizedLine)
            ?: AdGuardRuleParser.parseLine(raw)
            ?: return@withContext Result.failure(IllegalArgumentException("域名规则格式无效"))

        val entity = BlockRuleEntity(
            pattern = parsed.pattern,
            rawLine = raw,
            addedAt = System.currentTimeMillis(),
            enabled = true,
            groupName = null,
            appScope = appScope?.takeIf { it.isNotBlank() } ?: parsed.appScope,
            appInverted = if (!appScope.isNullOrBlank()) appInverted else parsed.appInverted,
            isWildcard = parsed.isWildcard,
            important = important || parsed.important
        )

        val inserted = blockRuleDao.insertForSource(entity, "useradd", sourceEnabled = true)
        if (inserted) {
            blockListManager.syncCachedPattern(entity.pattern)
            syncDnsAndPassthrough()
            refreshAll()
            Result.success("已添加域名黑名单规则")
        } else {
            Result.failure(IllegalArgumentException("该域名规则已存在"))
        }
    }

    suspend fun editRule(
        item: BlacklistItem,
        newPattern: String,
        newAppScope: String? = null,
        newAppInverted: Boolean = false,
        newImportant: Boolean = false
    ): Result<String> = withContext(Dispatchers.IO) {
        val trimmed = newPattern.trim()
        if (trimmed.isEmpty()) return@withContext Result.failure(IllegalArgumentException("规则内容不能为空"))

        if (item.type == BlacklistType.URL) {
            val line = if (trimmed.startsWith("||")) trimmed.removePrefix("||") else trimmed
            goUrlRuleManager.delete(item.id)
            val added = goUrlRuleManager.addRule(line)
            syncUrlRules()
            refreshAll()
            return@withContext if (added) Result.success("URL 规则已修改") else Result.failure(IllegalArgumentException("修改失败"))
        } else {
            val normalizedLine = when {
                trimmed.startsWith("||") -> trimmed
                trimmed.startsWith("0.0.0.0 ") || trimmed.startsWith("127.0.0.1 ") -> trimmed
                else -> "||$trimmed^"
            }
            val parsed = AdGuardRuleParser.parseLine(normalizedLine)
                ?: AdGuardRuleParser.parseLine(trimmed)
                ?: return@withContext Result.failure(IllegalArgumentException("域名格式无效"))

            blockRuleDao.deleteById(item.id)
            val entity = BlockRuleEntity(
                pattern = parsed.pattern,
                rawLine = trimmed,
                addedAt = System.currentTimeMillis(),
                enabled = item.enabled,
                groupName = item.groupName,
                appScope = newAppScope?.takeIf { it.isNotBlank() },
                appInverted = if (!newAppScope.isNullOrBlank()) newAppInverted else false,
                isWildcard = parsed.isWildcard,
                important = newImportant
            )
            blockRuleDao.insertForSource(entity, "useradd", sourceEnabled = item.enabled)
            if (item.pattern != entity.pattern) {
                blockListManager.syncCachedPattern(item.pattern)
            }
            blockListManager.syncCachedPattern(entity.pattern)
            syncDnsAndPassthrough()
            refreshAll()
            Result.success("域名规则已修改")
        }
    }

    fun clearUserBlacklist() {
        viewModelScope.launch(Dispatchers.IO) {
            blockRuleDao.deleteUserRules()
            goUrlRuleDao.deleteByKindAndSource(GoUrlRuleKind.BLOCK, GoUrlRuleManager.USER_SOURCE)
            syncDnsAndPassthrough()
            syncUrlRules()
            refreshAll()
        }
    }

    private fun syncDnsAndPassthrough() {
        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
            getApplication(),
            refreshBlock = true,
            refreshAllow = false,
            refreshRewrite = false,
            scope = RuleScope.DNS
        )
    }

    private fun syncUrlRules() {
        RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(getApplication())
    }

    private fun BlockRuleEntity.toItem(
        isUserRule: Boolean = true,
        isSubscription: Boolean = false,
        subscriptionName: String? = null,
        masterEnabled: Boolean = true
    ): BlacklistItem = BlacklistItem(
        id = id,
        pattern = pattern,
        rawLine = rawLine,
        type = BlacklistType.DOMAIN,
        groupName = groupName,
        appScope = appScope,
        appInverted = appInverted,
        isWildcard = isWildcard,
        important = important,
        enabled = enabled,
        masterEnabled = masterEnabled,
        effectiveEnabled = enabled && masterEnabled,
        addedAt = addedAt,
        isUserRule = isUserRule,
        isSubscription = isSubscription,
        subscriptionName = subscriptionName
    )

    private fun GoUrlRuleEntity.toItem(
        isUserRule: Boolean = true,
        isSubscription: Boolean = false,
        subscriptionName: String? = null,
        masterEnabled: Boolean = true
    ): BlacklistItem = BlacklistItem(
        id = id,
        pattern = pattern,
        rawLine = rawLine,
        type = BlacklistType.URL,
        groupName = null,
        appScope = null,
        appInverted = false,
        isWildcard = false,
        important = false,
        enabled = enabled,
        masterEnabled = masterEnabled,
        effectiveEnabled = enabled && masterEnabled,
        addedAt = addedAt,
        isUserRule = isUserRule,
        isSubscription = isSubscription,
        subscriptionName = subscriptionName
    )
}
