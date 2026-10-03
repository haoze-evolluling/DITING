package com.haoze.diting.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.data.entity.AllowRuleEntity
import com.haoze.diting.data.entity.CosmeticRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleEntity
import com.haoze.diting.data.entity.GoUrlRuleKind
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.ui.settings.RuleSettingsAccess
import com.haoze.diting.vpn.AdGuardRuleParser
import com.haoze.diting.vpn.AllowListManager
import com.haoze.diting.vpn.CosmeticRuleManager
import com.haoze.diting.vpn.DefaultWhitelistSeeder
import com.haoze.diting.vpn.GoUrlRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class WhitelistViewModel(
    application: Application,
    private val dataset: RuleDataset = RuleDataset.NORMAL
) : AndroidViewModel(application) {

    private val settings = RuleSettingsAccess(dataset)
    private val db = RuleDatabases.forDataset(application, dataset)
    private val allowRuleDao = db.allowRuleDao()
    private val goUrlRuleDao = db.goUrlRuleDao()
    private val cosmeticRuleDao = db.cosmeticRuleDao()
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

    private val _allowEditDefault = MutableStateFlow(settings.isAllowEditDefaultWhitelist(application))
    val allowEditDefault: StateFlow<Boolean> = _allowEditDefault.asStateFlow()

    private var activated = false

    fun activate() {
        if (!activated) {
            activated = true
            viewModelScope.launch(Dispatchers.IO) {
                // The DNS dataset has no preset whitelist and starts empty.
                if (dataset == RuleDataset.NORMAL) {
                    DefaultWhitelistSeeder.ensureInitialized(getApplication(), AppDatabase.getInstance(getApplication()))
                }
                refreshAll()
            }
        } else {
            refreshAll()
        }
    }

    fun setAllowEditDefault(enabled: Boolean) {
        _allowEditDefault.value = enabled
        settings.setAllowEditDefaultWhitelist(getApplication(), enabled)
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
            val domainRulesEnabled = settings.isMasterEnabled(getApplication())
            val addressRulesOperational = settings.isAddressRulesOperational(getApplication())

            val totalDomains = if (domainRulesEnabled) allowRuleDao.enabledPatternsCount() else 0
            val presetTotal = allowRuleDao.countBySource(DefaultWhitelistSeeder.SOURCE_PRESET)
            val presetEnabled = if (domainRulesEnabled) allowRuleDao.enabledCountBySource(DefaultWhitelistSeeder.SOURCE_PRESET) else 0
            val userTotal = allowRuleDao.userRulesCount()
            val userEnabled = if (domainRulesEnabled) allowRuleDao.enabledUserRulesCount() else 0
            val subscriptionTotal = allowRuleDao.subscriptionRulesCount()
            val subscriptionEnabled = if (domainRulesEnabled) allowRuleDao.enabledSubscriptionRulesCount() else 0
            val urlAllowCount = goUrlRuleDao.count(GoUrlRuleKind.ALLOW)
            val urlEnabled = if (addressRulesOperational) goUrlRuleDao.enabledCount(GoUrlRuleKind.ALLOW) else 0
            val cosmeticCount = if (dataset == RuleDataset.NORMAL) cosmeticRuleDao.allowRulesCount() else 0
            val cosmeticEnabled = if (dataset == RuleDataset.NORMAL) cosmeticRuleDao.enabledAllowCount() else 0
            val totalActive = totalDomains + urlEnabled + cosmeticEnabled

            _stats.value = WhitelistStats(
                totalDomains = totalDomains,
                presetTotal = presetTotal,
                presetEnabled = presetEnabled,
                userTotal = userTotal,
                userEnabled = userEnabled,
                subscriptionTotal = subscriptionTotal,
                subscriptionEnabled = subscriptionEnabled,
                urlAllowCount = urlAllowCount,
                cosmeticCount = cosmeticCount,
                totalActive = totalActive
            )
        }
    }

    fun loadPage(page: Int) {
        viewModelScope.launch(Dispatchers.IO) {
            val query = _searchQuery.value.trim().lowercase()
            val currentFilter = _filter.value
            val domainRulesEnabled = settings.isMasterEnabled(getApplication())
            val addressRulesOperational = settings.isAddressRulesOperational(getApplication())

            val domainEntities = when (currentFilter) {
                WhitelistFilter.ALL, WhitelistFilter.DOMAIN -> {
                    val preset = allowRuleDao.bySource(DefaultWhitelistSeeder.SOURCE_PRESET)
                    val user = allowRuleDao.userRules()
                    val subs = allowRuleDao.subscriptionRules()
                    (user + preset + subs).distinctBy { it.id }
                }
                WhitelistFilter.PRESET -> allowRuleDao.bySource(DefaultWhitelistSeeder.SOURCE_PRESET)
                WhitelistFilter.USER_ADDED -> allowRuleDao.userRules()
                WhitelistFilter.SUBSCRIPTION -> allowRuleDao.subscriptionRules()
                WhitelistFilter.URL, WhitelistFilter.COSMETIC -> emptyList()
            }

            val domainRuleIds = domainEntities.map { it.id }
            val domainSources = if (domainRuleIds.isNotEmpty()) allowRuleDao.sourcesForRuleIds(domainRuleIds) else emptyList()
            val domainSourcesByRuleId = domainSources.groupBy { it.ruleId }

            val allUrlEntities = when (currentFilter) {
                WhitelistFilter.ALL, WhitelistFilter.URL -> goUrlRuleDao.byKind(GoUrlRuleKind.ALLOW)
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

            val allCosmeticEntities = if (dataset == RuleDataset.NORMAL) {
                when (currentFilter) {
                    WhitelistFilter.ALL, WhitelistFilter.COSMETIC -> cosmeticRuleDao.allowRules()
                    WhitelistFilter.USER_ADDED -> {
                        val cosmetics = cosmeticRuleDao.allowRules()
                        val ids = cosmetics.map { it.id }
                        val sources = if (ids.isNotEmpty()) cosmeticRuleDao.sourcesForRuleIds(ids) else emptyList()
                        val sourcesByRuleId = sources.groupBy { it.ruleId }
                        cosmetics.filter { entity ->
                            val src = sourcesByRuleId[entity.id].orEmpty()
                            src.isEmpty() || src.any { it.source == "useradd" || !it.source.startsWith("sub_") }
                        }
                    }
                    WhitelistFilter.SUBSCRIPTION -> {
                        val cosmetics = cosmeticRuleDao.allowRules()
                        val ids = cosmetics.map { it.id }
                        val sources = if (ids.isNotEmpty()) cosmeticRuleDao.sourcesForRuleIds(ids) else emptyList()
                        val sourcesByRuleId = sources.groupBy { it.ruleId }
                        cosmetics.filter { entity ->
                            val src = sourcesByRuleId[entity.id].orEmpty()
                            src.any { it.source.startsWith("sub_") }
                        }
                    }
                    else -> emptyList()
                }
            } else emptyList()

            val cosmeticRuleIds = allCosmeticEntities.map { it.id }
            val cosmeticSources = if (cosmeticRuleIds.isNotEmpty()) cosmeticRuleDao.sourcesForRuleIds(cosmeticRuleIds) else emptyList()
            val cosmeticSourcesByRuleId = cosmeticSources.groupBy { it.ruleId }

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

            val cosmeticItems = allCosmeticEntities.map { entity ->
                val sources = cosmeticSourcesByRuleId[entity.id].orEmpty()
                val isSub = sources.any { it.source.startsWith("sub_") }
                val isUser = sources.isEmpty() || sources.any { it.source == "useradd" || !it.source.startsWith("sub_") }
                val subName = sources.firstOrNull { it.source.startsWith("sub_") }?.let { subscriptionsMap[it.source]?.name }
                entity.toItem(
                    isUserRule = isUser,
                    isSubscription = isSub,
                    subscriptionName = subName,
                    masterEnabled = addressRulesOperational
                )
            }

            val combined = (domainItems + urlItems + cosmeticItems)
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
            when (item.type) {
                WhitelistType.DOMAIN -> {
                    allowListManager.toggleRule(item.id, enabled)?.let {
                        RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                            getApplication(),
                            "allow",
                            it,
                            RuleScope.DNS,
                            dataset = dataset
                        )
                    }
                }
                WhitelistType.URL -> {
                    goUrlRuleManager.setEnabled(item.id, enabled)
                    syncUrlRules()
                }
                WhitelistType.COSMETIC -> {
                    cosmeticRuleDao.setEnabled(item.id, enabled)
                    CosmeticRuleManager.getInstance(getApplication()).compileAllToCss()
                    syncUrlRules()
                }
            }
            refreshAll()
        }
    }

    fun deleteRule(item: WhitelistItem) {
        viewModelScope.launch(Dispatchers.IO) {
            when (item.type) {
                WhitelistType.DOMAIN -> {
                    allowListManager.deleteRule(item.id)?.let {
                        RuntimeDnsSettingsRefresher.syncRuleIfRunning(
                            getApplication(),
                            "allow",
                            it,
                            RuleScope.DNS,
                            dataset = dataset
                        )
                    }
                }
                WhitelistType.URL -> {
                    goUrlRuleManager.delete(item.id)
                    syncUrlRules()
                }
                WhitelistType.COSMETIC -> {
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

        // Check if cosmetic exception rule
        if (raw.contains("#@#")) {
            if (dataset == RuleDataset.DNS_MODE) {
                return@withContext Result.failure(IllegalArgumentException("元素规则仅普通模式支持"))
            }
            val parsedCat = AdGuardRuleParser.parseCategorizedLine(raw)
            val cosmeticRule = parsedCat.cosmeticRules.firstOrNull()
                ?: return@withContext Result.failure(IllegalArgumentException("元素放行规则格式无效"))
            val entity = CosmeticRuleEntity(
                domain = cosmeticRule.domain.ifEmpty { appScope.orEmpty() },
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
                Result.success("已添加元素放行规则")
            } else {
                Result.failure(IllegalArgumentException("该元素放行规则已存在"))
            }
        }

        // Check if URL allow rule
        val isHttpUrl = raw.startsWith("http://", ignoreCase = true) ||
                raw.startsWith("https://", ignoreCase = true) ||
                raw.startsWith("@@http://", ignoreCase = true) ||
                raw.startsWith("@@https://", ignoreCase = true)

        if (isHttpUrl) {
            if (dataset == RuleDataset.DNS_MODE) {
                return@withContext Result.failure(IllegalArgumentException("URL 规则仅普通模式支持"))
            }
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

        if (item.type == WhitelistType.COSMETIC) {
            if (!trimmed.contains("#@#")) {
                return@withContext Result.failure(IllegalArgumentException("元素放行规则格式无效 (需包含 #@#)"))
            }
            val parsedCat = AdGuardRuleParser.parseCategorizedLine(trimmed)
            val cosmeticRule = parsedCat.cosmeticRules.firstOrNull()
                ?: return@withContext Result.failure(IllegalArgumentException("元素放行规则格式无效"))
            cosmeticRuleDao.deleteRule(item.id)
            val entity = CosmeticRuleEntity(
                domain = cosmeticRule.domain.ifEmpty { newAppScope.orEmpty() },
                selector = cosmeticRule.selector,
                rawLine = trimmed,
                addedAt = System.currentTimeMillis(),
                enabled = item.enabled
            )
            val inserted = cosmeticRuleDao.insertForSource(entity, "useradd", sourceEnabled = item.enabled)
            CosmeticRuleManager.getInstance(getApplication()).compileAllToCss()
            syncUrlRules()
            refreshAll()
            return@withContext if (inserted) Result.success("元素放行规则已修改") else Result.failure(IllegalArgumentException("修改失败"))
        } else if (item.type == WhitelistType.URL) {
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
            // The DNS dataset has no preset whitelist to reset.
            if (dataset == RuleDataset.NORMAL) {
                DefaultWhitelistSeeder.seed(getApplication(), AppDatabase.getInstance(getApplication()), forceReset = true)
            }
            syncDnsAndPassthrough()
            refreshAll()
        }
    }

    fun clearUserWhitelist() {
        viewModelScope.launch(Dispatchers.IO) {
            allowRuleDao.deleteUserRules()
            goUrlRuleDao.deleteByKindAndSource(com.haoze.diting.data.entity.GoUrlRuleKind.ALLOW, GoUrlRuleManager.USER_SOURCE)
            if (dataset == RuleDataset.NORMAL) {
                cosmeticRuleDao.deleteUserAllowRules()
                CosmeticRuleManager.getInstance(getApplication()).compileAllToCss()
            }
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
            scope = RuleScope.DNS,
            dataset = dataset
        )
    }

    private fun syncUrlRules() {
        // URL rules only matter to the VPN mode's traffic inspection.
        if (dataset == RuleDataset.NORMAL) {
            RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(getApplication())
        }
    }
}
