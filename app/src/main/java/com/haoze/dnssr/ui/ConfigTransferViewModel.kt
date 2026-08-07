package com.haoze.dnssr.ui

import android.app.Application
import android.net.Uri
import android.os.SystemClock
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

enum class ConfigTransferOperation {
    IDLE,
    EXPORTING,
    IMPORTING
}

class ConfigTransferViewModel(application: Application) : AndroidViewModel(application) {
    private val manager by lazy { ConfigTransferManager(application) }

    private val _operation = MutableStateFlow(ConfigTransferOperation.IDLE)
    val operation: StateFlow<ConfigTransferOperation> = _operation.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _importProgress = MutableStateFlow(ConfigImportProgress(0, 0, "正在读取配置文件"))
    val importProgress: StateFlow<ConfigImportProgress> = _importProgress.asStateFlow()

    private val _ruleExportProgress = MutableStateFlow(0f)
    val ruleExportProgress: StateFlow<Float> = _ruleExportProgress.asStateFlow()

    private val _ruleExportProgressText = MutableStateFlow("正在准备导出")
    val ruleExportProgressText: StateFlow<String> = _ruleExportProgressText.asStateFlow()

    fun export(uri: Uri, selection: ConfigExportSelection) {
        runOperation(ConfigTransferOperation.EXPORTING) {
            val context = getApplication<Application>()
            val content = manager.export(selection)
            context.contentResolver.openOutputStream(uri, "wt")?.bufferedWriter().use { writer ->
                requireNotNull(writer) { "无法打开导出文件" }
                writer.write(content)
            }
            "配置已导出"
        }
    }

    fun exportRules(uri: Uri, request: RuleExportRequest) {
        _ruleExportProgress.value = 0f
        _ruleExportProgressText.value = "正在准备导出"
        runOperation(ConfigTransferOperation.EXPORTING) {
            val context = getApplication<Application>()
            val result = manager.exportRules(request) { progress, text ->
                _ruleExportProgress.value = progress
                _ruleExportProgressText.value = text
            }
            context.contentResolver.openOutputStream(uri, "wt")?.bufferedWriter().use { writer ->
                requireNotNull(writer) { "无法打开导出文件" }
                val chunkSize = 8 * 1024
                val totalLength = result.content.length.coerceAtLeast(1)
                result.content.chunked(chunkSize).forEachIndexed { index, chunk ->
                    writer.write(chunk)
                    val writtenLength = minOf((index + 1) * chunkSize, result.content.length)
                    _ruleExportProgress.value = 0.6f + 0.4f * writtenLength / totalLength
                    _ruleExportProgressText.value = "正在写入文件"
                }
            }
            "${request.scope.name} ${request.type.displayName}已导出：${result.summary()}"
        }
    }

    fun import(uri: Uri) {
        _importProgress.value = ConfigImportProgress(0, 0, "正在读取配置文件")
        runOperation(ConfigTransferOperation.IMPORTING, MIN_IMPORT_DURATION_MILLIS) {
            val context = getApplication<Application>()
            val content = context.contentResolver.openInputStream(uri)?.bufferedReader().use { reader ->
                requireNotNull(reader) { "无法读取配置文件" }
                reader.readText()
            }
            val result = manager.import(content) { progress ->
                _importProgress.value = progress
            }
            if (result.excludedAppsUpdated || result.blockedAppsUpdated) {
                RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
            } else if (result.appAllowlistUpdated) {
                RuntimeDnsSettingsRefresher.refreshAppAllowlistIfRunning(context)
            } else {
                RuntimeDnsSettingsRefresher.refreshIfRunning(context, "configuration_imported")
            }
            result.message()
        }
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

    private companion object {
        const val MIN_IMPORT_DURATION_MILLIS = 3_000L
    }
}
