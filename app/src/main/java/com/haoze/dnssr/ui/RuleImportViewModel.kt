package com.haoze.dnssr.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.RuleOperationScheduler
import com.haoze.dnssr.vpn.RuleOperationType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

class RuleImportViewModel(application: Application) : AndroidViewModel(application) {
    private val _message = MutableStateFlow<String?>(null)
    val message = _message.asStateFlow()
    private val _progress = MutableStateFlow(-1 to 0)
    val progress = _progress.asStateFlow()
    private val _importing = MutableStateFlow(false)
    val importing = _importing.asStateFlow()

    init {
        viewModelScope.launch {
            WorkManager.getInstance(application)
                .getWorkInfosByTagFlow(RuleOperationScheduler.TAG)
                .collectLatest(::applyWorkState)
        }
    }

    fun importLocalSubscription(uri: Uri, name: String, kind: String, scope: RuleScope) {
        persistReadPermission(uri)
        enqueue(
            RuleOperationScheduler.enqueue(
                getApplication(),
                RuleOperationType.ADD_LOCAL_SUBSCRIPTION,
                name = name,
                uri = uri,
                kind = kind,
                scope = scope.storageValue
            ).id
        )
    }

    fun restoreHttpsBackup(uri: Uri) {
        persistReadPermission(uri)
        enqueue(
            RuleOperationScheduler.enqueue(
                getApplication(),
                RuleOperationType.IMPORT_HTTPS_RULE_BACKUP,
                uri = uri,
                scope = RuleScope.HTTPS.storageValue
            ).id
        )
    }

    fun clearMessage() {
        _message.value = null
    }

    private fun persistReadPermission(uri: Uri) {
        runCatching {
            getApplication<Application>().contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
    }

    private fun enqueue(workId: java.util.UUID) {
        viewModelScope.launch {
            WorkManager.getInstance(getApplication<Application>()).getWorkInfoByIdFlow(workId)
                .collectLatest { info ->
                    if (info?.state?.isFinished == true) {
                        val result = info.outputData.getString(RuleOperationScheduler.KEY_MESSAGE)
                        val success = info.outputData.getBoolean(RuleOperationScheduler.KEY_SUCCESS, false)
                        _message.value = if (success) result else "操作失败：$result"
                        return@collectLatest
                    }
                }
        }
    }

    private fun applyWorkState(infos: List<WorkInfo>) {
        val active = infos.firstOrNull { info ->
            val isActive = info.state == WorkInfo.State.RUNNING || info.state == WorkInfo.State.ENQUEUED ||
                info.state == WorkInfo.State.BLOCKED
            val type = info.progress.getString(RuleOperationScheduler.KEY_TYPE)?.let {
                runCatching { RuleOperationType.valueOf(it) }.getOrNull()
            }
            isActive && type in setOf(
                RuleOperationType.ADD_LOCAL_SUBSCRIPTION,
                RuleOperationType.IMPORT_HTTPS_RULE_BACKUP
            )
        }
        _importing.value = active != null
        _progress.value = active?.let {
            it.progress.getInt(RuleOperationScheduler.KEY_CURRENT, -1) to
                it.progress.getInt(RuleOperationScheduler.KEY_TOTAL, 0)
        } ?: (-1 to 0)
    }
}
