package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.AllowRuleEntity
import com.haoze.dnssr.data.entity.GoUrlRuleEntity
import com.haoze.dnssr.data.entity.GoUrlRuleKind
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.AdGuardRuleParser
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.DefaultWhitelistSeeder
import com.haoze.dnssr.vpn.GoUrlRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class WhitelistType {
    DOMAIN,
    URL
}

enum class WhitelistFilter(val labelResName: String) {
    ALL("全部"),
    USER_ADDED("用户自定义"),
    PRESET("默认预设"),
    SUBSCRIPTION("规则订阅"),
    DOMAIN("域名放行"),
    URL("URL 放行")
}

data class WhitelistItem(
    val id: Long,
    val pattern: String,
    val rawLine: String,
    val type: WhitelistType,
    val isPreset: Boolean,
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

data class WhitelistStats(
    val totalDomains: Int = 0,
    val presetTotal: Int = 0,
    val presetEnabled: Int = 0,
    val userTotal: Int = 0,
    val userEnabled: Int = 0,
    val subscriptionTotal: Int = 0,
    val subscriptionEnabled: Int = 0,
    val urlAllowCount: Int = 0,
    val totalActive: Int = 0
)

class WhitelistViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getInstance(application)
    private val allowRuleDao = db.allowRuleDao()
    private val goUrlRuleDao = db.goUrlRuleDao()
    private val subscriptionDao = db.subscriptionDao()
    private val allowListManager = AllowListManager(allowRuleDao, scope = RuleScope.DNS)
    private val goUrlRuleManager = GoUrlRuleManager(goUrlRuleDao)

    private val pageSize = 100

    private val _stats = MutableStateFlow(WhitelistStats())
    val stats: StateFlow<WhitelistStats> = _stats.asStateFlow()

    private val _items = MutableStateFlow<List<WhitelistItem>>(emptyList())
    val items: StateFlow<List<WhitelistItem>> = _items.asStateFlow()

    private val _currentPage = MutableStateFlow(1)
    val currentPage: StateFlow<Int> = _currentPage.asStateFlow()

    private val _totalPages = MutableStateFlow(1)
    val totalPages: StateFlow<Int> = _totalPages.asStateFlow()

    private val _totalCount = MutableStateFlow(0)
    val totalCount: StateFlow<Int> = _totalCount.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private val _filter = MutableStateFlow(WhitelistFilter.ALL)
    val filter: StateFlow<WhitelistFilter> = _filter.asStateFlow()

    private val _allowEditDefault = MutableStateFlow(AppSettings.isAllowEditDefaultWhitelist(application))
    val allowEditDefault: StateFlow<Boolean> = _allowEditDefault.asStateFlow()

    private var activated = false

    fun activate() {
        if (!activated) {
            activated = true
            viewModelScope.launch(Dispatchers.IO) {
                DefaultWhitelistSeeder.ensureInitialized(getApplication(), db)
                refreshAll()
            }
        } else {
            refreshAll()
        }
    }

    fun setAllowEditDefault(enabled: Boolean) {
        _allowEditDefault.value = enabled
        AppSettings.setAllowEditDefaultWhitelist(getApplication(), enabled)
    }

    fun setFilter(newFilter: WhitelistFilter) {
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

            val totalDomains = if (domainRulesEnabled) allowRuleDao.enabledPatternsCount() else 0
            val presetTotal = allowRuleDao.countBySource(DefaultWhitelistSeeder.SOURCE_PRESET)
            val presetEnabled = if (domainRulesEnabled) allowRuleDao.enabledCountBySource(DefaultWhitelistSeeder.SOURCE_PRESET) else 0
            val userTotal = allowRuleDao.userRulesCount()
            val userEnabled = if (domainRulesEnabled) allowRuleDao.enabledUserRulesCount() else 0
            val subscriptionTotal = allowRuleDao.subscriptionRulesCount()
            val subscriptionEnabled = if (domainRulesEnabled) allowRuleDao.enabledSubscriptionRulesCount() else 0
            val urlAllowCount = goUrlRuleDao.count(GoUrlRuleKind.ALLOW)
            val urlEnabled = if (addressRulesOperational) goUrlRuleDao.enabledCount(GoUrlRuleKind.ALLOW) else 0
            val totalActive = totalDomains + urlEnabled

            _stats.value = WhitelistStats(
                totalDomains = totalDomains,
                presetTotal = presetTotal,
                presetEnabled = presetEnabled,
                userTotal = userTotal,
                userEnabled = userEnabled,
                subscriptionTotal = subscriptionTotal,
                subscriptionEnabled = subscriptionEnabled,
                urlAllowCount = urlAllowCount,
                totalActive = totalActive
            )
        }
    }

    fun loadPage(page: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val query = _searchQuery.value.trim().lowercase()
            val currentFilter = _filter.value
            val domainRulesEnabled = AppSettings.isDomainRulesEnabled(getApplication())
            val addressRulesOperational = AppSettings.isAddressRulesFullyOperational(getApplication())

            val domainEntities = when (currentFilter) {
                WhitelistFilter.ALL, WhitelistFilter.DOMAIN -> {
                    val preset = allowRuleDao.bySource(DefaultWhitelistSeeder.SOURCE_PRESET)
                    val user = allowRuleDao.userRules()
                    val subs = allowRuleDao.subscriptionRules()
                    (user + preset + subs).distinctBy { it.id }
                }
                WhitelistFilter.PRESET -> {
                    allowRuleDao.bySource(DefaultWhitelistSeeder.SOURCE_PRESET)
                }
                WhitelistFilter.USER_ADDED -> {
                    allowRuleDao.userRules()
                }
                WhitelistFilter.SUBSCRIPTION -> {
                    allowRuleDao.subscriptionRules()
                }
                WhitelistFilter.URL -> emptyList()
            }

            val domainRuleIds = domainEntities.map { it.id }
            val domainSources = if (domainRuleIds.isNotEmpty()) allowRuleDao.sourcesForRuleIds(domainRuleIds) else emptyList()
            val domainSourcesByRuleId = domainSources.groupBy { it.ruleId }

            val allUrlEntities = when (currentFilter) {
                WhitelistFilter.ALL, WhitelistFilter.URL -> {
                    goUrlRuleDao.byKind(GoUrlRuleKind.ALLOW)
                }
                WhitelistFilter.USER_ADDED -> {
                    val urls = goUrlRuleDao.byKind(GoUrlRuleKind.ALLOW)
                    val urlRuleIds = urls.map { it.id }
                    val urlSources = if (urlRuleIds.isNotEmpty()) goUrlRuleDao.sourcesForRuleIds(urlRuleIds) else emptyList()
                    val urlSourcesByRuleId = urlSources.groupBy { it.ruleId }
                    urls.filter { entity ->
                        val sources = urlSourcesByRuleId[entity.id].orEmpty()
                        sources.isEmpty() || sources.any { it.source == GoUrlRuleManager.USER_SOURCE || !it.source.startsWith("sub_") }
                    }
                }
                WhitelistFilter.SUBSCRIPTION -> {
                    val urls = goUrlRuleDao.byKind(GoUrlRuleKind.ALLOW)
                    val urlRuleIds = urls.map { it.id }
                    val urlSources = if (urlRuleIds.isNotEmpty()) goUrlRuleDao.sourcesForRuleIds(urlRuleIds) else emptyList()
                    val urlSourcesByRuleId = urlSources.groupBy { it.ruleId }
                    urls.filter { entity ->
                        val sources = urlSourcesByRuleId[entity.id].orEmpty()
                        sources.any { it.source.startsWith("sub_") }
                    }
                }
                else -> emptyList()
            }

            val urlRuleIds = allUrlEntities.map { it.id }
            val urlSources = if (urlRuleIds.isNotEmpty()) goUrlRuleDao.sourcesForRuleIds(urlRuleIds) else emptyList()
            val urlSourcesByRuleId = urlSources.groupBy { it.ruleId }

            val subscriptionsMap = subscriptionDao.all().associateBy { "sub_${it.id}" }

            val domainItems = domainEntities.map { entity ->
                val sources = domainSourcesByRuleId[entity.id].orEmpty()
                val isPreset = sources.any { it.source == DefaultWhitelistSeeder.SOURCE_PRESET }
                val isSub = sources.any { it.source.startsWith("sub_") }
                val isUser = sources.any { it.source == DefaultWhitelistSeeder.SOURCE_USER || (it.source != DefaultWhitelistSeeder.SOURCE_PRESET && !it.source.startsWith("sub_")) } || (!isPreset && !isSub)
                val subName = sources.firstOrNull { it.source.startsWith("sub_") }?.let { subscriptionsMap[it.source]?.name }
                entity.toItem(
                    isPreset = isPreset,
                    isUserRule = isUser,
                    isSubscription = isSub,
                    subscriptionName = subName,
                    masterEnabled = domainRulesEnabled
                )
            }

            val urlItems = allUrlEntities.map { entity ->
                val sources = urlSourcesByRuleId[entity.id].orEmpty()
                val isSub = sources.any { it.source.startsWith("sub_") }
                val isUser = sources.isEmpty() || sources.any { it.source == GoUrlRuleManager.USER_SOURCE || !it.source.startsWith("sub_") }
                val subName = sources.firstOrNull { it.source.startsWith("sub_") }?.let { subscriptionsMap[it.source]?.name }
                entity.toItem(
                    isUserRule = isUser,
                    isSubscription = isSub,
                    subscriptionName = subName,
                    masterEnabled = addressRulesOperational
                )
            }

            val combined = (domainItems + urlItems)
                .distinctBy { "${it.type}_${it.id}" }
                .filter { item ->
                    if (query.isEmpty()) true
                    else item.pattern.lowercase().contains(query) ||
                            item.rawLine.lowercase().contains(query) ||
                            (item.groupName?.lowercase()?.contains(query) == true) ||
                            (item.appScope?.lowercase()?.contains(query) == true) ||
                            (item.subscriptionName?.lowercase()?.contains(query) == true)
                }.sortedWith(
                    compareBy<WhitelistItem> { it.isPreset }
                        .thenByDescending { it.addedAt }
                )

            val total = combined.size
            val pages = if (total == 0) 1 else (total + pageSize - 1) / pageSize
            val safePage = page.coerceIn(1, pages)
            val offset = (safePage - 1) * pageSize
            val pagedItems = combined.drop(offset).take(pageSize)

            withContext(Dispatchers.Main) {
                _items.value = pagedItems
                _currentPage.value = safePage
                _totalPages.value = pages
                _totalCount.value = total
            }
        }
    }

    fun toggleRule(item: WhitelistItem, enabled: Boolean) {
        viewModelScope.launch(Dispatchers.IO) {
            if (item.type == WhitelistType.DOMAIN) {
                allowListManager.toggleRule(item.id, enabled)?.let {
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                        getApplication(),
                        "allow",
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

    fun deleteRule(item: WhitelistItem) {
        viewModelScope.launch(Dispatchers.IO) {
            if (item.type == WhitelistType.DOMAIN) {
                allowListManager.deleteRule(item.id)?.let {
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                        getApplication(),
                        "allow",
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

        // Check if URL allow rule
        val isHttpUrl = raw.startsWith("http://", ignoreCase = true) ||
                raw.startsWith("https://", ignoreCase = true) ||
                raw.startsWith("@@http://", ignoreCase = true) ||
                raw.startsWith("@@https://", ignoreCase = true)

        if (isHttpUrl) {
            val line = if (raw.startsWith("@@")) raw else "@@$raw"
            val success = goUrlRuleManager.addRule(line)
            if (success) {
                syncUrlRules()
                refreshAll()
                return@withContext Result.success("已添加 URL 放行规则")
            } else {
                return@withContext Result.failure(IllegalArgumentException("URL 格式无效或规则已存在"))
            }
        }

        // Domain allow rule
        val normalizedLine = when {
            raw.startsWith("@@") -> raw
            raw.startsWith("||") -> "@@$raw"
            else -> "@@||$raw^"
        }

        val parsed = AdGuardRuleParser.parseAllowLine(normalizedLine)
            ?: AdGuardRuleParser.parseAllowLine("@@$raw")
            ?: return@withContext Result.failure(IllegalArgumentException("域名规则格式无效"))

        val entity = AllowRuleEntity(
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

        val inserted = allowRuleDao.insertForSource(entity, DefaultWhitelistSeeder.SOURCE_USER, sourceEnabled = true)
        if (inserted) {
            allowListManager.syncCachedPattern(entity.pattern)
            syncDnsAndPassthrough()
            refreshAll()
            Result.success("已添加域名白名单规则")
        } else {
            Result.failure(IllegalArgumentException("该域名规则已存在"))
        }
    }

    suspend fun editRule(
        item: WhitelistItem,
        newPattern: String,
        newAppScope: String? = null,
        newAppInverted: Boolean = false,
        newImportant: Boolean = false
    ): Result<String> = withContext(Dispatchers.IO) {
        val trimmed = newPattern.trim()
        if (trimmed.isEmpty()) return@withContext Result.failure(IllegalArgumentException("规则内容不能为空"))

        if (item.type == WhitelistType.URL) {
            val line = if (trimmed.startsWith("@@")) trimmed else "@@$trimmed"
            goUrlRuleManager.delete(item.id)
            val added = goUrlRuleManager.addRule(line)
            syncUrlRules()
            refreshAll()
            return@withContext if (added) Result.success("URL 规则已修改") else Result.failure(IllegalArgumentException("修改失败"))
        } else {
            val normalizedLine = when {
                trimmed.startsWith("@@") -> trimmed
                trimmed.startsWith("||") -> "@@$trimmed"
                else -> "@@||$trimmed^"
            }
            val parsed = AdGuardRuleParser.parseAllowLine(normalizedLine)
                ?: AdGuardRuleParser.parseAllowLine("@@$trimmed")
                ?: return@withContext Result.failure(IllegalArgumentException("域名格式无效"))

            allowRuleDao.deleteById(item.id)
            val source = if (item.isPreset) DefaultWhitelistSeeder.SOURCE_PRESET else DefaultWhitelistSeeder.SOURCE_USER
            val entity = AllowRuleEntity(
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
            allowRuleDao.insertForSource(entity, source, sourceEnabled = item.enabled)
            if (item.pattern != entity.pattern) {
                allowListManager.syncCachedPattern(item.pattern)
            }
            allowListManager.syncCachedPattern(entity.pattern)
            syncDnsAndPassthrough()
            refreshAll()
            Result.success("域名规则已修改")
        }
    }

    fun resetPresetWhitelist() {
        viewModelScope.launch(Dispatchers.IO) {
            DefaultWhitelistSeeder.seed(getApplication(), db, forceReset = true)
            syncDnsAndPassthrough()
            refreshAll()
        }
    }

    fun clearUserWhitelist() {
        viewModelScope.launch(Dispatchers.IO) {
            allowRuleDao.deleteUserRules()
            goUrlRuleDao.deleteByKindAndSource(com.haoze.dnssr.data.entity.GoUrlRuleKind.ALLOW, GoUrlRuleManager.USER_SOURCE)
            syncDnsAndPassthrough()
            syncUrlRules()
            refreshAll()
        }
    }

    private fun syncDnsAndPassthrough() {
        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
            getApplication(),
            refreshBlock = false,
            refreshAllow = true,
            refreshRewrite = false,
            scope = RuleScope.DNS
        )
    }

    private fun syncUrlRules() {
        RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(getApplication())
    }

    private fun AllowRuleEntity.toItem(
        isPreset: Boolean,
        isUserRule: Boolean = true,
        isSubscription: Boolean = false,
        subscriptionName: String? = null,
        masterEnabled: Boolean = true
    ): WhitelistItem = WhitelistItem(
        id = id,
        pattern = pattern,
        rawLine = rawLine,
        type = WhitelistType.DOMAIN,
        isPreset = isPreset,
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
    ): WhitelistItem = WhitelistItem(
        id = id,
        pattern = pattern,
        rawLine = rawLine,
        type = WhitelistType.URL,
        isPreset = false,
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
