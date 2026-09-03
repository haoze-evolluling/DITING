package com.haoze.dnssr.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.WorkManager
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.RuleOperationScheduler
import com.haoze.dnssr.vpn.RuleOperationType
import com.haoze.dnssr.vpn.RewriteRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class RuleManagementViewModel(application: Application) : AndroidViewModel(application) {

    private var ruleScope = RuleScope.DNS
    private var addressOnly = false
    private fun rewriteRuleManager() = RewriteRuleManager(AppDatabase.getInstance(getApplication<Application>()).rewriteRuleDao(), java.io.File(getApplication<Application>().filesDir, "rule-index"), ruleScope)

    private val _rewriteRuleCount = MutableStateFlow(0)
    val rewriteRuleCount: StateFlow<Int> = _rewriteRuleCount.asStateFlow()
    val mirrorTemplates = AppDatabase.getInstance(application).mirrorTemplateDao().observeAll()

    private var activated = false

    fun activate(scope: RuleScope, addressOnly: Boolean = false) {
        if (ruleScope != scope || this.addressOnly != addressOnly) activated = false
        ruleScope = scope
        this.addressOnly = addressOnly
        if (!activated) {
            activated = true
            loadRuleCount()
        }
    }

    fun loadRuleCount() {
        val scope = ruleScope
        viewModelScope.launch(Dispatchers.IO) {
            val database = AppDatabase.getInstance(getApplication<Application>())
            val rewriteCount = RewriteRuleManager(
                database.rewriteRuleDao(),
                java.io.File(getApplication<Application>().filesDir, "rule-index"),
                scope
            ).count()
            withContext(Dispatchers.Main) {
                if (ruleScope != scope || this@RuleManagementViewModel.addressOnly != addressOnly) return@withContext
                _rewriteRuleCount.value = rewriteCount
            }
        }
    }

    fun importRules(uri: Uri, onResult: (String) -> Unit) {
        runCatching {
            getApplication<Application>().contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
        observeResult(
            RuleOperationScheduler.enqueue(
                getApplication(), RuleOperationType.IMPORT_RULES, uri = uri
            ).id,
            onResult
        )
    }

    fun addRewriteRule(domain: String, targetType: String, targetValue: String, onResult: (String) -> Unit) {
        val scope = ruleScope
        viewModelScope.launch(Dispatchers.IO) {
            val success = rewriteRuleManager().addRule(domain, targetType, targetValue)
            if (success) {
                RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(
                    getApplication(), false, false, true, scope
                )
            }
            withContext(Dispatchers.Main) {
                onResult(if (success) "已添加覆写域名" else "域名、目标格式无效、规则冲突或已存在")
                loadRuleCount()
            }
        }
    }

    fun addMirrorTemplate(name: String, template: String, onResult: (String) -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            val result = runCatching {
                validateMirrorTemplate(name, template)
                AppDatabase.getInstance(getApplication<Application>()).mirrorTemplateDao().insert(
                    MirrorTemplateEntity(name = name.trim(), template = template.trim())
                )
            }
            withContext(Dispatchers.Main) {
                val context = getApplication<Application>()
                onResult(
                    if (result.isSuccess) "已添加镜像站模板"
                    else localizedText(context, result.exceptionOrNull()?.message ?: "添加失败")
                )
            }
        }
    }

    fun editMirrorTemplate(template: MirrorTemplateEntity, name: String, address: String, onResult: (String) -> Unit) {
        viewModelScope.launch(Dispatchers.IO) {
            val result = runCatching {
                validateMirrorTemplate(name, address)
                AppDatabase.getInstance(getApplication<Application>()).mirrorTemplateDao().update(
                    template.copy(name = name.trim(), template = address.trim())
                )
            }
            withContext(Dispatchers.Main) {
                val context = getApplication<Application>()
                onResult(
                    if (result.isSuccess) "已更新镜像站模板"
                    else localizedText(context, result.exceptionOrNull()?.message ?: "更新失败")
                )
            }
        }
    }

    fun deleteMirrorTemplate(template: MirrorTemplateEntity) {
        viewModelScope.launch(Dispatchers.IO) {
            AppDatabase.getInstance(getApplication<Application>()).mirrorTemplateDao().delete(template)
        }
    }

    private fun validateMirrorTemplate(name: String, template: String) {
        require(name.trim().isNotEmpty()) { "镜像站名称不能为空" }
        require(template.trim().startsWith("http://") || template.trim().startsWith("https://")) { "模板必须使用 HTTP 或 HTTPS" }
        require(listOf("{url}", "{urlEncoded}", "{scheme}", "{host}", "{path}", "{pathAndQuery}").any { it in template }) { "模板缺少 URL 占位符" }
    }

    fun importHostsRules(uri: Uri, onResult: (String) -> Unit) {
        runCatching {
            getApplication<Application>().contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
        observeResult(
            RuleOperationScheduler.enqueue(
                getApplication(), RuleOperationType.IMPORT_HOSTS_RULES, uri = uri
            ).id,
            onResult
        )
    }

    private fun observeResult(workId: java.util.UUID, onResult: (String) -> Unit) {
        viewModelScope.launch {
            WorkManager.getInstance(getApplication<Application>())
                .getWorkInfoByIdFlow(workId)
                .collect { info ->
                    if (info?.state?.isFinished == true) {
                        val success = info.outputData.getBoolean(RuleOperationScheduler.KEY_SUCCESS, false)
                        val message = info.outputData.getString(RuleOperationScheduler.KEY_MESSAGE)
                            ?: "操作失败"
                        onResult(if (success) message else "操作失败：$message")
                        loadRuleCount()
                        return@collect
                    }
                }
        }
    }

}

