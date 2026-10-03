package com.haoze.diting.ui

import android.app.Application
import android.net.Uri
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.ui.transfer.ConfigExporter
import com.haoze.diting.ui.transfer.ConfigImporter
import com.haoze.diting.ui.transfer.ConfigTransferParser
import com.haoze.diting.vpn.DnsProvider
import com.haoze.diting.vpn.GoUrlRuleManager

enum class ConfigTransferOperation {
    IDLE,
    EXPORTING,
    IMPORTING
}

class ConfigTransferViewModel(application: Application) : AndroidViewModel(application) {
    private val exporter by lazy { ConfigExporter(application) }
    private val importer by lazy { ConfigImporter(application) }
    private val database by lazy { AppDatabase.getInstance(application) }

    private val _operation = MutableStateFlow(ConfigTransferOperation.IDLE)
    val operation: StateFlow<ConfigTransferOperation> = _operation.asStateFlow()

    private val _stats = MutableStateFlow(ConfigDashboardStats())
    val stats: StateFlow<ConfigDashboardStats> = _stats.asStateFlow()

    init {
        loadStats()
    }

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _showImportDialog = MutableStateFlow(false)
    val showImportDialog: StateFlow<Boolean> = _showImportDialog.asStateFlow()

    private val _isImportFinished = MutableStateFlow(false)
    val isImportFinished: StateFlow<Boolean> = _isImportFinished.asStateFlow()

    private val _importResult = MutableStateFlow<ConfigImportResult?>(null)
    val importResult: StateFlow<ConfigImportResult?> = _importResult.asStateFlow()

    private val _importError = MutableStateFlow<String?>(null)
    val importError: StateFlow<String?> = _importError.asStateFlow()

    private val _importLogs = MutableStateFlow<List<String>>(emptyList())
    val importLogs: StateFlow<List<String>> = _importLogs.asStateFlow()

    private val _importProgress = MutableStateFlow(ConfigImportProgress(0, 0, "正在读取配置文件"))
    val importProgress: StateFlow<ConfigImportProgress> = _importProgress.asStateFlow()

    fun export(uri: Uri, selection: ConfigExportSelection) {
        runOperation(ConfigTransferOperation.EXPORTING) {
            val context = getApplication<Application>()
            val content = exporter.export(selection)
            context.contentResolver.openOutputStream(uri, "wt")?.bufferedWriter().use { writer ->
                requireNotNull(writer) { "无法打开导出文件" }
                writer.write(content)
            }
            "配置已导出"
        }
    }

    private var importJob: Job? = null

    fun cancelImport() {
        if (_operation.value != ConfigTransferOperation.IMPORTING) return
        importJob?.cancel()
        importJob = null
        _importError.value = "导入已取消"
        _importLogs.value = _importLogs.value + "已取消导入"
        _isImportFinished.value = true
        _operation.value = ConfigTransferOperation.IDLE
        loadStats()
    }

    fun import(uri: Uri) {
        if (_operation.value != ConfigTransferOperation.IDLE) return
        _operation.value = ConfigTransferOperation.IMPORTING
        _showImportDialog.value = true
        _isImportFinished.value = false
        _importResult.value = null
        _importError.value = null
        val initialLogs = mutableListOf("正在读取配置文件...")
        _importLogs.value = initialLogs.toList()
        _importProgress.value = ConfigImportProgress(0, 0, "正在读取配置文件")

        importJob?.cancel()
        importJob = viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            try {
                val content = context.contentResolver.openInputStream(uri)?.bufferedReader().use { reader ->
                    requireNotNull(reader) { "无法读取配置文件" }
                    reader.readText()
                }
                val config = ConfigTransferParser.parseAndValidate(content)
                val result = importer.import(config) { progress ->
                    _importProgress.value = progress
                    progress.log?.let { logText ->
                        synchronized(initialLogs) {
                            initialLogs.add(logText)
                            _importLogs.value = initialLogs.toList()
                        }
                    }
                }
                if (result.excludedAppsUpdated || result.blockedAppsUpdated || result.httpInspectionUpdated || result.outboundProxyUpdated) {
                    RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
                }
                if (result.appAllowlistUpdated) {
                    RuntimeDnsSettingsRefresher.refreshAppAllowlistIfRunning(context)
                }
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, "configuration_imported")
                withContext(Dispatchers.Main) {
                    _importResult.value = result
                    _isImportFinished.value = true
                    _operation.value = ConfigTransferOperation.IDLE
                    importJob = null
                    loadStats()
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    val errorMsg = e.message ?: "未知错误"
                    _importError.value = errorMsg
                    synchronized(initialLogs) {
                        initialLogs.add("导入失败：$errorMsg")
                        _importLogs.value = initialLogs.toList()
                    }
                    _isImportFinished.value = true
                    _operation.value = ConfigTransferOperation.IDLE
                    importJob = null
                }
            }
        }
    }

    fun loadStats() {
        viewModelScope.launch(Dispatchers.IO) {
            val context = getApplication<Application>()
            val providersCount = DnsProvider.loadUserProviders(context).size
            val subscriptionsCount = try {
                database.subscriptionDao().allRemote().size
            } catch (e: Exception) {
                0
            }
            val customRulesCount = try {
                val block = database.blockRuleDao().bySource("useradd").size
                val allow = database.allowRuleDao().bySource("useradd").size
                val rewrite = database.rewriteRuleDao().rulesBySource("useradd").size
                val address = database.goUrlRuleDao().rulesBySource(GoUrlRuleManager.USER_SOURCE).size
                block + allow + rewrite + address
            } catch (e: Exception) {
                0
            }
            val managedAppsCount = try {
                val excluded = AppRulesSettingsStore.getExcludedAppPackages(context)
                val blocked = AppRulesSettingsStore.getBlockedAppPackages(context)
                val allowlist = AppRulesSettingsStore.getAppAllowlistRuleMap(context)
                val inspection = AppRulesSettingsStore.getHttpInspectionAppPackages(context)
                (excluded + blocked + allowlist.keys + inspection).distinct().size
            } catch (e: Exception) {
                0
            }
            _stats.value = ConfigDashboardStats(
                customProvidersCount = providersCount,
                subscriptionsCount = subscriptionsCount,
                customRulesCount = customRulesCount,
                managedAppsCount = managedAppsCount
            )
        }
    }

    fun dismissImportDialog() {
        if (_operation.value == ConfigTransferOperation.IMPORTING) return
        _showImportDialog.value = false
        _importResult.value = null
        _importError.value = null
    }

    fun clearMessage() {
        _message.value = null
    }

    private fun runOperation(
        operation: ConfigTransferOperation,
        minimumDurationMillis: Long = 0,
        block: suspend () -> String
    ) {
        if (_operation.value != ConfigTransferOperation.IDLE) return
        _operation.value = operation
        viewModelScope.launch(Dispatchers.IO) {
            val startedAt = SystemClock.elapsedRealtime()
            val context = getApplication<Application>()
            val message = try {
                block()
            } catch (e: Exception) {
                localizedText(context, "操作失败：${localizedText(context, e.message ?: "未知错误")}")
            }
            delay((minimumDurationMillis - (SystemClock.elapsedRealtime() - startedAt)).coerceAtLeast(0))
            withContext(Dispatchers.Main) {
                _message.value = message
                _operation.value = ConfigTransferOperation.IDLE
            }
        }
    }
}
