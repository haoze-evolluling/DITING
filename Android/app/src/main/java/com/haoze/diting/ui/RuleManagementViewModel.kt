package com.haoze.diting.ui

import android.app.Application
import android.content.Intent
import android.net.Uri
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.WorkManager
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.data.entity.MirrorTemplateEntity
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.core.rule.RuleOperationScheduler
import com.haoze.diting.core.rule.RuleOperationType
import com.haoze.diting.core.rule.RewriteRuleManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class RuleManagementViewModel(
    application: Application,
    private val dataset: RuleDataset = RuleDataset.NORMAL
) : AndroidViewModel(application) {

    private var ruleScope = RuleScope.DNS
    private var addressOnly = false
    private fun rewriteRuleManager() = RewriteRuleManager(
        RuleDatabases.forDataset(getApplication<Application>(), dataset).rewriteRuleDao(),
        // The DNS dataset keeps pure in-memory caches; rule-index/ belongs to VPN mode.
        if (dataset == RuleDataset.NORMAL) java.io.File(getApplication<Application>().filesDir, "rule-index") else null,
        ruleScope
    )

    private val _rewriteRuleCount = MutableStateFlow(0)
    val rewriteRuleCount: StateFlow<Int> = _rewriteRuleCount.asStateFlow()
    val mirrorTemplates = RuleDatabases.forDataset(application, dataset).mirrorTemplateDao().observeAll()

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
            val rewriteCount = RewriteRuleManager(
                RuleDatabases.forDataset(getApplication<Application>(), dataset).rewriteRuleDao(),
                if (dataset == RuleDataset.NORMAL) java.io.File(getApplication<Application>().filesDir, "rule-index") else null,
                scope
            ).count()
            withContext(Dispatchers.Main) {
                if (ruleScope != scope || this@RuleManagementViewModel.addressOnly != addressOnly) return@withContext
                _rewriteRuleCount.value = rewriteCount
            }
        }
    }

    /**
     * Imports a local rule file as [kind] rules. The type must be chosen by the
     * caller: a file is no longer classified automatically.
     */
    fun importRules(
        uri: Uri,
        kind: String = com.haoze.diting.data.entity.SubscriptionKind.DOMAIN,
        onResult: (String) -> Unit
    ) {
        runCatching {
            getApplication<Application>().contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        }
        observeResult(
            RuleOperationScheduler.enqueue(
                getApplication(),
                RuleOperationType.IMPORT_RULES,
                uri = uri,
                kind = com.haoze.diting.data.entity.SubscriptionKind.normalize(kind)
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
                    getApplication(), false, false, true, scope, dataset
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
                RuleDatabases.forDataset(getApplication<Application>(), dataset).mirrorTemplateDao().insert(
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
                RuleDatabases.forDataset(getApplication<Application>(), dataset).mirrorTemplateDao().update(
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
            RuleDatabases.forDataset(getApplication<Application>(), dataset).mirrorTemplateDao().delete(template)
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

