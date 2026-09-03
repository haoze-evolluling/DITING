package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.AllowRuleEntity
import com.haoze.dnssr.data.entity.BlockRuleEntity
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.AdGuardRuleParser
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.BlockListManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

internal class AppRuleViewModel(application: Application) : AndroidViewModel(application) {

    private val db = AppDatabase.getInstance(application)
    private val blockRuleDao = db.blockRuleDao()
    private val allowRuleDao = db.allowRuleDao()
    private val scope = RuleScope.DNS

    private val blockListManager = BlockListManager(blockRuleDao, scope = scope)
    private val allowListManager = AllowListManager(allowRuleDao, scope = scope)

    private val _selectedApp = MutableStateFlow<InstalledApp?>(null)
    val selectedApp: StateFlow<InstalledApp?> = _selectedApp.asStateFlow()

    private val _appRuleCounts = MutableStateFlow<Map<String, Int>>(emptyMap())
    val appRuleCounts: StateFlow<Map<String, Int>> = _appRuleCounts.asStateFlow()

    private val _appAllowlistMap = MutableStateFlow<Map<String, Set<String>>>(emptyMap())
    val appAllowlistMap: StateFlow<Map<String, Set<String>>> = _appAllowlistMap.asStateFlow()

    private val _isAppAllowlistMasterEnabled = MutableStateFlow(false)
    val isAppAllowlistMasterEnabled: StateFlow<Boolean> = _isAppAllowlistMasterEnabled.asStateFlow()

    private val _selectedAppAllowlistDomains = MutableStateFlow<Set<String>>(emptySet())
    val selectedAppAllowlistDomains: StateFlow<Set<String>> = _selectedAppAllowlistDomains.asStateFlow()

    private val _fullBlockEnabled = MutableStateFlow(false)
    val fullBlockEnabled: StateFlow<Boolean> = _fullBlockEnabled.asStateFlow()

    private val _blockRules = MutableStateFlow<List<BlockRuleEntity>>(emptyList())
    val blockRules: StateFlow<List<BlockRuleEntity>> = _blockRules.asStateFlow()

    private val _allowRules = MutableStateFlow<List<AllowRuleEntity>>(emptyList())
    val allowRules: StateFlow<List<AllowRuleEntity>> = _allowRules.asStateFlow()

    init {
        loadAllData()
    }

    fun loadAllData() {
        loadAppRuleCounts()
        loadAllowlistData()
    }

    fun loadAllowlistData() {
        val context = getApplication<Application>()
        _isAppAllowlistMasterEnabled.value = AppSettings.isAppAllowlistEnabled(context)
        _appAllowlistMap.value = AppSettings.getAppAllowlistRuleMap(context)
    }

    fun setMasterAllowlistEnabled(enabled: Boolean) {
        val context = getApplication<Application>()
        _isAppAllowlistMasterEnabled.value = enabled
        AppSettings.setAppAllowlistEnabled(context, enabled)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
    }

    fun selectApp(app: InstalledApp?) {
        _selectedApp.value = app
        if (app != null) {
            loadRulesForApp(app.packageName)
        } else {
            _blockRules.value = emptyList()
            _allowRules.value = emptyList()
            _selectedAppAllowlistDomains.value = emptySet()
            _fullBlockEnabled.value = false
            loadAllData()
        }
    }

    fun loadAppRuleCounts() {
        viewModelScope.launch(Dispatchers.IO) {
            val blockScopes = blockRuleDao.appScopes()
            val allowScopes = allowRuleDao.appScopes()
            val allPackages = (blockScopes + allowScopes)
                .flatMap { it.split('|') }
                .map { it.trim().removePrefix("~") }
                .filter { it.isNotEmpty() }
                .distinct()

            val counts = mutableMapOf<String, Int>()
            for (pkg in allPackages) {
                val blockCount = blockRuleDao.countByAppScope(pkg)
                val allowCount = allowRuleDao.countByAppScope(pkg)
                counts[pkg] = blockCount + allowCount
            }
            withContext(Dispatchers.Main) {
                _appRuleCounts.value = counts
            }
        }
    }

    fun loadRulesForApp(packageName: String) {
        val context = getApplication<Application>()
        val allowlistDomains = AppSettings.getAppAllowlistDomainsForApp(context, packageName)
        _selectedAppAllowlistDomains.value = allowlistDomains

        viewModelScope.launch(Dispatchers.IO) {
            val blocks = blockRuleDao.allByAppScope(packageName)
            val allows = allowRuleDao.allByAppScope(packageName)
            val hasFullBlock = blocks.any { it.pattern == "*" && it.enabled && !it.appInverted }

            withContext(Dispatchers.Main) {
                _blockRules.value = blocks
                _allowRules.value = allows
                _fullBlockEnabled.value = hasFullBlock
            }
        }
    }

    fun addAllowlistDomain(rawInput: String, onResult: (String, Boolean) -> Unit) {
        val app = _selectedApp.value ?: return
        val parsed = AdGuardRuleParser.parseAllowLine(rawInput.trim())?.pattern
        if (parsed.isNullOrBlank()) {
            onResult("请输入有效的域名", false)
            return
        }
        val context = getApplication<Application>()
        val current = _selectedAppAllowlistDomains.value.toMutableSet()
        if (current.contains(parsed)) {
            onResult("域名已存在", false)
            return
        }
        current.add(parsed)
        _selectedAppAllowlistDomains.value = current
        AppSettings.setAppAllowlistDomainsForApp(context, app.packageName, current)
        // Clean up conflict package lists
        AppSettings.setBlockedAppPackages(context, AppSettings.getBlockedAppPackages(context) - app.packageName)
        AppSettings.removeHttpInspectionAppPackages(context, setOf(app.packageName))
        AppSettings.setExcludedAppPackages(context, AppSettings.getExcludedAppPackages(context) - app.packageName)
        RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        loadAllowlistData()
        onResult("已添加放行域名: $parsed", true)
    }

    fun removeAllowlistDomain(domain: String) {
        val app = _selectedApp.value ?: return
        val context = getApplication<Application>()
        val current = _selectedAppAllowlistDomains.value.toMutableSet()
        current.remove(domain)
        _selectedAppAllowlistDomains.value = current
        AppSettings.setAppAllowlistDomainsForApp(context, app.packageName, current)
        RuntimeDnsSettingsRefresher.refreshAppAllowlistIfRunning(context)
        loadAllowlistData()
    }

    fun clearAllowlistDomainsForSelectedApp() {
        val app = _selectedApp.value ?: return
        val context = getApplication<Application>()
        _selectedAppAllowlistDomains.value = emptySet()
        AppSettings.removeAppAllowlistForApp(context, app.packageName)
        RuntimeDnsSettingsRefresher.refreshAppAllowlistIfRunning(context)
        loadAllowlistData()
    }

    fun clearAllAllowlistRules() {
        val context = getApplication<Application>()
        AppSettings.setAppAllowlistRuleMap(context, emptyMap())
        _appAllowlistMap.value = emptyMap()
        _selectedAppAllowlistDomains.value = emptySet()
        RuntimeDnsSettingsRefresher.refreshAppAllowlistIfRunning(context)
    }

    fun toggleFullBlockTemplate(enabled: Boolean, onResult: (String) -> Unit = {}) {
        val app = _selectedApp.value ?: return
        viewModelScope.launch(Dispatchers.IO) {
            val pkg = app.packageName
            val existing = blockRuleDao.allByAppScope(pkg).firstOrNull { it.pattern == "*" && !it.appInverted }
            val context = getApplication<Application>()

            if (enabled) {
                if (existing != null) {
                    blockRuleDao.setEnabled(existing.id, true)
                    blockListManager.syncCachedPattern("*")
                } else {
                    val ruleStr = "*\$app=$pkg"
                    blockListManager.addRule(ruleStr)
                }
                RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "block", "*", scope)
            } else {
                if (existing != null) {
                    blockRuleDao.deleteById(existing.id)
                    blockListManager.syncCachedPattern("*")
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "block", "*", scope)
                }
            }
            loadRulesForApp(pkg)
            loadAppRuleCounts()
            withContext(Dispatchers.Main) {
                onResult(if (enabled) "已开启全外联拦截模式" else "已关闭全外联拦截模式")
            }
        }
    }

    fun addAppRule(
        pattern: String,
        isAllow: Boolean,
        important: Boolean = false,
        isWildcard: Boolean = false,
        onResult: (String) -> Unit
    ) {
        val app = _selectedApp.value ?: return
        viewModelScope.launch(Dispatchers.IO) {
            val pkg = app.packageName
            val trimmed = pattern.trim()
            val cleanPattern = when {
                trimmed.startsWith("@@") -> trimmed.removePrefix("@@").trim()
                trimmed.startsWith("||") -> trimmed.removePrefix("||").trimEnd('^').trim()
                else -> trimmed.trimEnd('^').trim()
            }
            val ruleString = buildString {
                if (isAllow) append("@@")
                if (cleanPattern == "*") {
                    append("*")
                } else {
                    append("||").append(cleanPattern).append("^")
                }
                append("\$app=").append(pkg)
                if (important) append(",important")
            }

            val context = getApplication<Application>()
            val success = if (isAllow) {
                val added = allowListManager.addRule(ruleString)
                if (added) {
                    val parsed = AdGuardRuleParser.parseAllowLine(ruleString)
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "allow", parsed?.pattern ?: cleanPattern, scope)
                }
                added
            } else {
                val added = blockListManager.addRule(ruleString)
                if (added) {
                    val parsed = AdGuardRuleParser.parseLine(ruleString)
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "block", parsed?.pattern ?: cleanPattern, scope)
                }
                added
            }

            loadRulesForApp(pkg)
            loadAppRuleCounts()
            withContext(Dispatchers.Main) {
                onResult(if (success) "规则添加成功" else "规则格式无效或已存在")
            }
        }
    }

    fun toggleRule(id: Long, isAllow: Boolean, enabled: Boolean) {
        val app = _selectedApp.value ?: return
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            if (isAllow) {
                val pattern = allowListManager.toggleRule(id, enabled)
                if (pattern != null) {
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "allow", pattern, scope)
                }
            } else {
                val pattern = blockListManager.toggleRule(id, enabled)
                if (pattern != null) {
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "block", pattern, scope)
                }
            }
            loadRulesForApp(app.packageName)
            loadAppRuleCounts()
        }
    }

    fun deleteRule(id: Long, isAllow: Boolean) {
        val app = _selectedApp.value ?: return
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            if (isAllow) {
                val pattern = allowListManager.deleteRule(id)
                if (pattern != null) {
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "allow", pattern, scope)
                }
            } else {
                val pattern = blockListManager.deleteRule(id)
                if (pattern != null) {
                    RuntimeDnsSettingsRefresher.syncRuleIfRunning(context, "block", pattern, scope)
                }
            }
            loadRulesForApp(app.packageName)
            loadAppRuleCounts()
        }
    }
}

