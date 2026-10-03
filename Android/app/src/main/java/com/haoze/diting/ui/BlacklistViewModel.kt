package com.haoze.diting.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.data.entity.BlockRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleKind
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.settings.RuleSettingsAccess
import com.haoze.diting.vpn.AdGuardRuleParser
import com.haoze.diting.vpn.BlockListManager
import com.haoze.diting.vpn.GoUrlRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.vpn.CosmeticRuleManager

class BlacklistViewModel(
    application: Application,
    private val dataset: RuleDataset = RuleDataset.NORMAL
) : AndroidViewModel(application) {

    private val settings = RuleSettingsAccess(dataset)
    private val db = RuleDatabases.forDataset(application, dataset)
    private val blockRuleDao = db.blockRuleDao()
    private val goUrlRuleDao = db.goUrlRuleDao()
    private val cosmeticRuleDao = db.cosmeticRuleDao()
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
            val domainRulesEnabled = settings.isMasterEnabled(getApplication())
            val addressRulesOperational = settings.isAddressRulesOperational(getApplication())

            val totalDomains = if (domainRulesEnabled) blockRuleDao.enabledPatternsCount() else 0
            val userTotal = blockRuleDao.userRulesCount()
            val userEnabled = if (domainRulesEnabled) blockRuleDao.enabledUserRulesCount() else 0
            val urlBlockCount = goUrlRuleDao.count(GoUrlRuleKind.BLOCK)
            val urlEnabled = if (addressRulesOperational) goUrlRuleDao.enabledCount(GoUrlRuleKind.BLOCK) else 0
            val cosmeticCount = if (dataset == RuleDataset.NORMAL) cosmeticRuleDao.blockRulesCount() else 0
            val cosmeticEnabled = if (dataset == RuleDataset.NORMAL && addressRulesOperational) cosmeticRuleDao.enabledBlockCount() else 0
            val totalActive = totalDomains + urlEnabled + cosmeticEnabled

            _stats.value = BlacklistStats(
                totalDomains = totalDomains,
                userTotal = userTotal,
                userEnabled = userEnabled,
                urlBlockCount = urlBlockCount,
                cosmeticCount = cosmeticCount,
                totalActive = totalActive
            )
        }
    }

    fun loadPage(page: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val query = _searchQuery.value.trim()
            val currentFilter = _filter.value
            val domainRulesEnabled = settings.isMasterEnabled(getApplication())
            val addressRulesOperational = settings.isAddressRulesOperational(getApplication())
            val subscriptionsMap = subscriptionDao.all().associateBy { "sub_${it.id}" }

            // 1. URL block items
            val allUrlEntities = when (currentFilter) {
                BlacklistFilter.ALL, BlacklistFilter.USER_ADDED, BlacklistFilter.URL -> goUrlRuleDao.byKind(GoUrlRuleKind.BLOCK)
                else -> emptyList()
            }
            val filteredUrls = allUrlEntities.filter {
                query.isEmpty() || it.pattern.contains(query, ignoreCase = true) || it.rawLine.contains(query, ignoreCase = true)
            }
            val urlRuleIds = filteredUrls.map { it.id }
            val urlSources = if (urlRuleIds.isNotEmpty()) goUrlRuleDao.sourcesForRuleIds(urlRuleIds) else emptyList()
            val urlSourcesByRuleId = urlSources.groupBy { it.ruleId }
            val urlItems = filteredUrls.mapNotNull { entity ->
                val sources = urlSourcesByRuleId[entity.id].orEmpty()
                val isUser = sources.isEmpty() || sources.any { it.source == GoUrlRuleManager.USER_SOURCE || !it.source.startsWith("sub_") }
                val isSub = sources.any { it.source.startsWith("sub_") }
                if (currentFilter == BlacklistFilter.USER_ADDED && !isUser) return@mapNotNull null
                val subName = sources.firstOrNull { it.source.startsWith("sub_") }?.let { subscriptionsMap[it.source]?.name }
                entity.toItem(isUserRule = isUser, isSubscription = isSub, subscriptionName = subName, masterEnabled = addressRulesOperational)
            }

            // 2. Cosmetic block items
            val allCosmetics = if (dataset == RuleDataset.NORMAL) {
                when (currentFilter) {
                    BlacklistFilter.ALL, BlacklistFilter.USER_ADDED, BlacklistFilter.SUBSCRIPTION, BlacklistFilter.COSMETIC -> cosmeticRuleDao.blockRules()
                    else -> emptyList()
                }
            } else emptyList()
            val filteredCosmetics = allCosmetics.filter {
                query.isEmpty() || it.rawLine.contains(query, ignoreCase = true) || it.domain.contains(query, ignoreCase = true) || it.selector.contains(query, ignoreCase = true)
            }
            val cosmeticRuleIds = filteredCosmetics.map { it.id }
            val cosmeticSources = if (cosmeticRuleIds.isNotEmpty()) cosmeticRuleDao.sourcesForRuleIds(cosmeticRuleIds) else emptyList()
            val cosmeticSourcesByRuleId = cosmeticSources.groupBy { it.ruleId }
            val cosmeticItems = filteredCosmetics.mapNotNull { entity ->
                val sources = cosmeticSourcesByRuleId[entity.id].orEmpty()
                val isUser = sources.isEmpty() || sources.any { it.source == "useradd" || !it.source.startsWith("sub_") }
                val isSub = sources.any { it.source.startsWith("sub_") }
                if (currentFilter == BlacklistFilter.USER_ADDED && !isUser) return@mapNotNull null
                if (currentFilter == BlacklistFilter.SUBSCRIPTION && !isSub) return@mapNotNull null
                val subName = sources.firstOrNull { it.source.startsWith("sub_") }?.let { subscriptionsMap[it.source]?.name }
                entity.toItem(isUserRule = isUser, isSubscription = isSub, subscriptionName = subName, masterEnabled = addressRulesOperational)
            }

            val nonDomainItems = when (currentFilter) {
                BlacklistFilter.URL -> urlItems
                BlacklistFilter.COSMETIC -> cosmeticItems
                BlacklistFilter.SUBSCRIPTION -> cosmeticItems
                else -> cosmeticItems + urlItems
            }
            val nonDomainCount = nonDomainItems.size

            // 3. Domain count
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
                BlacklistFilter.URL, BlacklistFilter.COSMETIC -> 0
            }

            val total = nonDomainCount + domainCount
            val pages = if (total == 0) 1 else (total + pageSize - 1) / pageSize
            val safePage = page.coerceIn(1, pages)
            val offset = (safePage - 1) * pageSize

            val pagedNonDomain: List<BlacklistItem>
            val pagedDomainEntities: List<BlockRuleEntity>

            if (currentFilter == BlacklistFilter.URL || currentFilter == BlacklistFilter.COSMETIC) {
                pagedNonDomain = nonDomainItems.drop(offset).take(pageSize)
                pagedDomainEntities = emptyList()
            } else if (currentFilter == BlacklistFilter.DOMAIN) {
                pagedNonDomain = emptyList()
                pagedDomainEntities = queryDomainEntities(currentFilter, query, pageSize, offset)
            } else {
                if (offset < nonDomainCount) {
                    pagedNonDomain = nonDomainItems.drop(offset).take(pageSize)
                    val domainLimit = pageSize - pagedNonDomain.size
                    pagedDomainEntities = if (domainLimit > 0) queryDomainEntities(currentFilter, query, domainLimit, 0) else emptyList()
                } else {
                    pagedNonDomain = emptyList()
                    val domainOffset = offset - nonDomainCount
                    pagedDomainEntities = queryDomainEntities(currentFilter, query, pageSize, domainOffset)
                }
            }

            val domainRuleIds = pagedDomainEntities.map { it.id }
            val domainSources = if (domainRuleIds.isNotEmpty()) blockRuleDao.sourcesForRuleIds(domainRuleIds) else emptyList()
            val domainSourcesByRuleId = domainSources.groupBy { it.ruleId }

            val domainItems = pagedDomainEntities.map { entity ->
                val sources = domainSourcesByRuleId[entity.id].orEmpty()
                val isUser = sources.any { it.source == "useradd" || !it.source.startsWith("sub_") }
                val subSources = sources.filter { it.source.startsWith("sub_") }
                val isSub = subSources.isNotEmpty()
                val subName = subSources.firstOrNull()?.let { subscriptionsMap[it.source]?.name }
                entity.toItem(isUserRule = isUser, isSubscription = isSub, subscriptionName = subName, masterEnabled = domainRulesEnabled)
            }

            val combined = pagedNonDomain + domainItems

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
            when (item.type) {
                BlacklistType.DOMAIN -> {
                    blockListManager.toggleRule(item.id, enabled)?.let {
                        RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                            getApplication(), "block", it, RuleScope.DNS, dataset = dataset
                        )
                    }
                }
                BlacklistType.URL -> {
                    goUrlRuleManager.setEnabled(item.id, enabled)
                    syncUrlRules()
                }
                BlacklistType.COSMETIC -> {
                    cosmeticRuleDao.setEnabled(item.id, enabled)
                    CosmeticRuleManager.getInstance(getApplication()).compileAllToCss()
                    syncUrlRules()
                }
            }
            refreshAll()
        }
    }

    fun deleteRule(item: BlacklistItem) {
        viewModelScope.launch(Dispatchers.IO) {
            when (item.type) {
                BlacklistType.DOMAIN -> {
                    blockListManager.deleteRule(item.id)?.let {
                        RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                            getApplication(), "block", it, RuleScope.DNS, dataset = dataset
                        )
                    }
                }
                BlacklistType.URL -> {
                    goUrlRuleManager.delete(item.id)
                    syncUrlRules()
                }
                BlacklistType.COSMETIC -> {
                    cosmeticRuleDao.deleteRule(item.id)
                    CosmeticRuleManager.getInstance(getApplication()).compileAllToCss()
                    syncUrlRules()
                }
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

        if (raw.contains("##") || raw.contains("#@#") || raw.contains("#?#") || raw.contains("#$#")) {
            if (raw.contains("#@#")) {
                return@withContext Result.failure(IllegalArgumentException("该规则为放行规则，请在白名单中添加"))
            }
            if (dataset == RuleDataset.DNS_MODE) {
                return@withContext Result.failure(IllegalArgumentException("元素隐藏规则仅普通模式支持"))
            }
            val parsedCat = AdGuardRuleParser.parseCategorizedLine(raw)
            val cosmeticRule = parsedCat.cosmeticRules.firstOrNull()
                ?: return@withContext Result.failure(IllegalArgumentException("元素隐藏规则格式无效"))

            val entity = CosmeticRuleEntity(
                domain = cosmeticRule.domain,
                selector = cosmeticRule.selector,
                rawLine = raw,
                addedAt = System.currentTimeMillis(),
                enabled = true
            )
            val inserted = cosmeticRuleDao.insertForSource(entity, "useradd", sourceEnabled = true)
            return@withContext if (inserted) {
                CosmeticRuleManager.getInstance(getApplication()).compileAllToCss()
                syncUrlRules()
                refreshAll()
                Result.success("已添加元素隐藏规则")
            } else {
                Result.failure(IllegalArgumentException("该元素隐藏规则已存在"))
            }
        }

        // Check if URL block rule
        val isHttpUrl = raw.startsWith("http://", ignoreCase = true) ||
                raw.startsWith("https://", ignoreCase = true) ||
                raw.startsWith("||http://", ignoreCase = true) ||
                raw.startsWith("||https://", ignoreCase = true)

        if (isHttpUrl) {
            if (dataset == RuleDataset.DNS_MODE) {
                return@withContext Result.failure(IllegalArgumentException("URL 规则仅普通模式支持"))
            }
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

        if (item.type == BlacklistType.COSMETIC) {
            val parsedCat = AdGuardRuleParser.parseCategorizedLine(trimmed)
            val cosmeticRule = parsedCat.cosmeticRules.firstOrNull()
                ?: return@withContext Result.failure(IllegalArgumentException("元素隐藏规则格式无效"))
            cosmeticRuleDao.deleteRule(item.id)
            val entity = CosmeticRuleEntity(
                domain = cosmeticRule.domain,
                selector = cosmeticRule.selector,
                rawLine = trimmed,
                addedAt = System.currentTimeMillis(),
                enabled = item.enabled
            )
            val inserted = cosmeticRuleDao.insertForSource(entity, "useradd", sourceEnabled = item.enabled)
            CosmeticRuleManager.getInstance(getApplication()).compileAllToCss()
            syncUrlRules()
            refreshAll()
            return@withContext if (inserted) Result.success("元素隐藏规则已修改") else Result.failure(IllegalArgumentException("修改失败"))
        } else if (item.type == BlacklistType.URL) {
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
            cosmeticRuleDao.deleteUserBlockRules()
            CosmeticRuleManager.getInstance(getApplication()).compileAllToCss()
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
            scope = RuleScope.DNS,
            dataset = dataset
        )
    }

    private fun syncUrlRules() {
        // URL and cosmetic rules matter to VPN mode's traffic inspection.
        if (dataset == RuleDataset.NORMAL) {
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(getApplication())
        }
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

    private fun CosmeticRuleEntity.toItem(
        isUserRule: Boolean = true,
        isSubscription: Boolean = false,
        subscriptionName: String? = null,
        masterEnabled: Boolean = true
    ): BlacklistItem = BlacklistItem(
        id = id,
        pattern = rawLine.ifBlank { if (domain.isNotEmpty()) "$domain##$selector" else "##$selector" },
        rawLine = rawLine,
        type = BlacklistType.COSMETIC,
        groupName = null,
        appScope = domain.takeIf { it.isNotBlank() },
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
