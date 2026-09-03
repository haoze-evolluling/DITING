package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.R
import androidx.room.withTransaction
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.SubscriptionEntity
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.BlockListManager
import com.haoze.dnssr.vpn.SubscriptionManager
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateScheduler
import com.haoze.dnssr.vpn.RuleOperationScheduler
import com.haoze.dnssr.vpn.RuleOperationType
import com.haoze.dnssr.vpn.SubscriptionUpdateCoordinator
import com.haoze.dnssr.vpn.SubscriptionUpdateOutcome
import kotlinx.coroutines.Job
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class SubscriptionProgress(val current: Int = -1, val total: Int = 0)
data class SubscriptionRuleBreakdown(val blockCount: Int = 0, val allowCount: Int = 0, val rewriteCount: Int = 0)

class SubscriptionViewModel(application: Application) : AndroidViewModel(application) {

    private var ruleScope = RuleScope.DNS
    private fun subscriptionManager(): SubscriptionManager {
        val app = getApplication<Application>()
        val database = AppDatabase.getInstance(app)
        return SubscriptionManager(
            database,
            database.subscriptionDao(),
            BlockListManager(database.blockRuleDao(), scope = ruleScope, reloadCacheAfterChanges = false),
            AllowListManager(database.allowRuleDao(), scope = ruleScope, reloadCacheAfterChanges = false),
            com.haoze.dnssr.vpn.RewriteRuleManager(database.rewriteRuleDao(), java.io.File(app.filesDir, "rule-index"), ruleScope, reloadCacheAfterChanges = false),
            ruleScope
        )
    }

    private val _subscriptions = MutableStateFlow<List<SubscriptionEntity>>(emptyList())
    val subscriptions: StateFlow<List<SubscriptionEntity>> = _subscriptions.asStateFlow()
    private val _ruleBreakdowns = MutableStateFlow<Map<Long, SubscriptionRuleBreakdown>>(emptyMap())
    val ruleBreakdowns: StateFlow<Map<Long, SubscriptionRuleBreakdown>> = _ruleBreakdowns.asStateFlow()
    private var deletingSubscriptionIds = emptySet<Long>()
    private val _pendingSubscriptions = MutableStateFlow<List<SubscriptionEntity>>(emptyList())
    val pendingSubscriptions: StateFlow<List<SubscriptionEntity>> = _pendingSubscriptions.asStateFlow()
    private var subscriptionsJob: Job? = null
    private var nextPendingSubscriptionId = -1L
    private val _dnsImportCandidates = MutableStateFlow<List<SubscriptionEntity>>(emptyList())
    val dnsImportCandidates: StateFlow<List<SubscriptionEntity>> = _dnsImportCandidates.asStateFlow()
    val mirrorTemplates = AppDatabase.getInstance(application).mirrorTemplateDao().observeAll()
    val subscriptionGroups = AppDatabase.getInstance(application).subscriptionGroupDao().observeAll()
    val allSubscriptions = AppDatabase.getInstance(application).subscriptionDao().observeAll()

    private val _importing = MutableStateFlow(false)
    val importing: StateFlow<Boolean> = _importing.asStateFlow()
    private val _importingSubscriptionId = MutableStateFlow<Long?>(null)
    val importingSubscriptionId: StateFlow<Long?> = _importingSubscriptionId.asStateFlow()

    private val _updatingSubscriptionId = MutableStateFlow<Long?>(null)
    val updatingSubscriptionId: StateFlow<Long?> = _updatingSubscriptionId.asStateFlow()

    private val _message = MutableStateFlow<String?>(null)
    val message: StateFlow<String?> = _message.asStateFlow()

    private val _operationMessage = MutableStateFlow<String?>(null)
    val operationMessage: StateFlow<String?> = _operationMessage.asStateFlow()
    private val _progress = MutableStateFlow(SubscriptionProgress())
    val progress: StateFlow<SubscriptionProgress> = _progress.asStateFlow()

    init {
        viewModelScope.launch {
            val workManager = WorkManager.getInstance(application)
            combine(
                workManager.getWorkInfosByTagFlow(RuleOperationScheduler.TAG),
                workManager.getWorkInfosByTagFlow(SubscriptionAutoUpdateScheduler.WORK_TAG)
            ) { manual, automatic -> manual + automatic }
                .collectLatest(::applyBackgroundWorkState)
        }
    }

    fun activate(scope: RuleScope = RuleScope.DNS) {
        ruleScope = scope
        subscriptionsJob?.cancel()
        subscriptionsJob = viewModelScope.launch {
            AppDatabase.getInstance(getApplication<Application>()).subscriptionDao()
                .observeAll()
                .collect { subscriptions ->
                    _subscriptions.value = subscriptions.filterNot { it.id in deletingSubscriptionIds }
                    updateRuleBreakdowns(subscriptions)
                }
        }
        if (scope == RuleScope.HTTPS) loadDnsImportCandidates()
    }

    fun loadSubscriptions() {
        viewModelScope.launch(Dispatchers.IO) {
            loadSubscriptionsIntoState()
        }
    }

    fun addSubscription(
        url: String,
        name: String? = null,
        kind: String = com.haoze.dnssr.data.entity.SubscriptionKind.UNIFIED,
        mirrorTemplate: String? = null,
        mirrorFallback: Boolean = true,
        groupId: Long? = null,
        newGroupName: String? = null
    ) {
        viewModelScope.launch(Dispatchers.IO) {
            val resolvedGroupId = resolveGroupId(groupId, newGroupName).getOrElse {
        withContext(Dispatchers.Main) {
            val context = getApplication<Application>()
            _message.value = context.getString(
                R.string.subscription_group_create_failed,
                localizedText(context, it.message ?: "")
            )
        }
                return@launch
            }
            addSubscriptionInternal(url, name, kind, mirrorTemplate, mirrorFallback, resolvedGroupId)
        }
    }

    private fun addSubscriptionInternal(
        url: String,
        name: String?,
        kind: String,
        mirrorTemplate: String?,
        mirrorFallback: Boolean,
        groupId: Long?
    ) {
        val pendingSubscription = SubscriptionEntity(
            id = nextPendingSubscriptionId--,
            url = url.trim(),
            name = name?.trim()?.takeIf { it.isNotEmpty() } ?: url.trim(),
            kind = kind,
            importState = com.haoze.dnssr.data.entity.SubscriptionImportState.IMPORTING,
            mirrorTemplate = mirrorTemplate,
            mirrorFallback = mirrorFallback,
            groupId = groupId
        )
        _pendingSubscriptions.value = _pendingSubscriptions.value + pendingSubscription
        enqueueAndObserve(
            RuleOperationScheduler.enqueue(
                getApplication(), RuleOperationType.ADD_SUBSCRIPTION, url = url, name = name, kind = kind,
                mirrorTemplate = mirrorTemplate, mirrorFallback = mirrorFallback, groupId = groupId ?: -1,
                scope = ruleScope.storageValue
            ).id,
            pendingSubscription.id
        )
    }

    fun renameSubscription(id: Long, name: String) {
        viewModelScope.launch(Dispatchers.IO) {
            val result = subscriptionManager().renameSubscription(id, name)
            loadSubscriptionsIntoState()
            withContext(Dispatchers.Main) {
                _message.value = if (result.isSuccess) {
                    "已重命名规则订阅"
                } else {
                    localizedText(
                        getApplication<Application>(),
                        "重命名失败：${localizedText(getApplication<Application>(), result.exceptionOrNull()?.message ?: "")}"
                    )
                }
            }
        }
    }

    fun editSubscription(
        id: Long,
        url: String,
        name: String,
        mirrorTemplate: String?,
        mirrorFallback: Boolean,
        groupId: Long? = null,
        newGroupName: String? = null
    ) {
        viewModelScope.launch(Dispatchers.IO) {
            val resolvedGroupId = resolveGroupId(groupId, newGroupName).getOrElse {
            withContext(Dispatchers.Main) {
                val context = getApplication<Application>()
                _message.value = context.getString(
                    R.string.subscription_group_create_failed,
                    localizedText(context, it.message ?: "")
                )
            }
                return@launch
            }
            enqueueAndObserve(
                RuleOperationScheduler.enqueue(
                    getApplication(), RuleOperationType.EDIT_SUBSCRIPTION,
                    subscriptionId = id, url = url, name = name,
                    mirrorTemplate = mirrorTemplate, mirrorFallback = mirrorFallback, groupId = resolvedGroupId ?: -1,
                    scope = ruleScope.storageValue
                ).id
            )
        }
    }

    fun createGroup(name: String, autoUpdateEnabled: Boolean = true) {
        viewModelScope.launch(Dispatchers.IO) {
            val result = createGroupInternal(name, autoUpdateEnabled)
            withContext(Dispatchers.Main) {
                _message.value = result.fold(
                    onSuccess = { "已创建分组" },
                    onFailure = {
                        val context = getApplication<Application>()
                        localizedText(
                            context,
                            "创建分组失败：${localizedText(context, it.message ?: "")}"
                        )
                    }
                )
            }
        }
    }

    fun renameGroup(id: Long, name: String) = updateGroup(id, name = name)

    fun setGroupAutoUpdateEnabled(id: Long, enabled: Boolean) = updateGroup(id, autoUpdateEnabled = enabled)

    fun deleteGroup(id: Long) {
        viewModelScope.launch(Dispatchers.IO) {
            val database = AppDatabase.getInstance(getApplication<Application>())
            database.withTransaction {
                database.subscriptionDao().clearGroup(id)
                database.subscriptionGroupDao().deleteById(id)
            }
            withContext(Dispatchers.Main) { _message.value = getApplication<Application>().getString(R.string.subscription_group_deleted) }
        }
    }

    fun deleteGroupSubscriptions(groupId: Long) {
            _operationMessage.value = getApplication<Application>().getString(R.string.subscription_group_deleting)
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val database = AppDatabase.getInstance(getApplication<Application>())
                val subscriptions = database.subscriptionDao().byGroupId(groupId)
                val scope = RuleScope.DNS
                var hasRewrite = false
                subscriptions.forEach { subscription ->
                    if (subscription.kind == com.haoze.dnssr.data.entity.SubscriptionKind.REWRITE) {
                        hasRewrite = true
                    }
                    subscriptionManagerFor(scope).deleteSubscription(subscription.id)
                }
                if (subscriptions.isNotEmpty()) {
                    refreshSubscriptionRuleIndexes(hasRewrite, scope)
                }
                withContext(Dispatchers.Main) { _message.value = getApplication<Application>().getString(R.string.subscription_groups_deleted, subscriptions.size) }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    val context = getApplication<Application>()
                    _message.value = context.getString(
                        R.string.subscription_bulk_delete_failed,
                        localizedText(context, e.message ?: "")
                    )
                }
            } finally {
                _operationMessage.value = null
            }
        }
    }

    private fun subscriptionManagerFor(scope: RuleScope): SubscriptionManager {
        val app = getApplication<Application>()
        val database = AppDatabase.getInstance(app)
        return SubscriptionManager(
            database,
            database.subscriptionDao(),
            BlockListManager(database.blockRuleDao(), scope = scope, reloadCacheAfterChanges = false),
            AllowListManager(database.allowRuleDao(), scope = scope, reloadCacheAfterChanges = false),
            com.haoze.dnssr.vpn.RewriteRuleManager(database.rewriteRuleDao(), java.io.File(app.filesDir, "rule-index"), scope, reloadCacheAfterChanges = false),
            scope
        )
    }

    private suspend fun resolveGroupId(groupId: Long?, newGroupName: String?): Result<Long?> {
        if (newGroupName.isNullOrBlank()) return Result.success(groupId)
        return createGroupInternal(newGroupName, true).map { it.id }
    }

    private suspend fun createGroupInternal(name: String, autoUpdateEnabled: Boolean): Result<SubscriptionGroupEntity> {
        val trimmed = name.trim()
        if (trimmed.isEmpty()) return Result.failure(IllegalArgumentException("分组名称不能为空"))
        val dao = AppDatabase.getInstance(getApplication<Application>()).subscriptionGroupDao()
        if (dao.byName(trimmed) != null) return Result.failure(IllegalArgumentException("分组名称已存在"))
        return runCatching {
            SubscriptionGroupEntity(id = dao.insert(SubscriptionGroupEntity(name = trimmed, autoUpdateEnabled = autoUpdateEnabled)), name = trimmed, autoUpdateEnabled = autoUpdateEnabled)
        }
    }

    private fun updateGroup(id: Long, name: String? = null, autoUpdateEnabled: Boolean? = null) {
        viewModelScope.launch(Dispatchers.IO) {
            val dao = AppDatabase.getInstance(getApplication<Application>()).subscriptionGroupDao()
            try {
                if (name != null) {
                    val trimmed = name.trim()
                    require(trimmed.isNotEmpty()) { "分组名称不能为空" }
                    val sameName = dao.byName(trimmed)
                    require(sameName == null || sameName.id == id) { "分组名称已存在" }
                    dao.setName(id, trimmed)
                }
                if (autoUpdateEnabled != null) dao.setAutoUpdateEnabled(id, autoUpdateEnabled)
            withContext(Dispatchers.Main) { _message.value = getApplication<Application>().getString(R.string.subscription_group_updated) }
            } catch (e: Exception) {
            withContext(Dispatchers.Main) {
                val context = getApplication<Application>()
                _message.value = context.getString(
                    R.string.subscription_group_update_failed,
                    localizedText(context, e.message ?: "")
                )
            }
            }
        }
    }

    fun updateSubscription(id: Long) {
        enqueueAndObserve(
            RuleOperationScheduler.enqueue(
                getApplication(), RuleOperationType.UPDATE_SUBSCRIPTION, subscriptionId = id,
                scope = ruleScope.storageValue
            ).id
        )
    }

    fun updateAllSubscriptions() {
        enqueueAndObserve(
            RuleOperationScheduler.enqueue(
                getApplication(), RuleOperationType.UPDATE_ALL_SUBSCRIPTIONS,
                scope = ruleScope.storageValue
            ).id
        )
    }

    fun importDnsSubscriptions(ids: Set<Long>) {
        if (ruleScope != RuleScope.HTTPS || ids.isEmpty()) return
        viewModelScope.launch(Dispatchers.IO) {
            val candidates = _dnsImportCandidates.value.filter { it.id in ids }
            candidates.forEach { subscription ->
                enqueueAndObserve(
                    RuleOperationScheduler.enqueue(
                        getApplication(),
                        RuleOperationType.ADD_SUBSCRIPTION,
                        url = subscription.url,
                        name = subscription.name,
                        kind = subscription.kind,
                        mirrorTemplate = subscription.mirrorTemplate,
                        mirrorFallback = subscription.mirrorFallback,
                        scope = RuleScope.HTTPS.storageValue
                    ).id
                )
            }
        }
    }

    fun deleteSubscription(id: Long) {
        viewModelScope.launch {
            deletingSubscriptionIds += id
            _subscriptions.value = _subscriptions.value.filterNot { it.id == id }
            _operationMessage.value = getApplication<Application>().getString(R.string.subscription_deleting)
            try {
                withContext(Dispatchers.IO) {
                    val subscription = AppDatabase.getInstance(getApplication<Application>()).subscriptionDao().byId(id)
                    subscriptionManager().deleteSubscription(id)
                    val isRewrite = subscription?.kind == com.haoze.dnssr.data.entity.SubscriptionKind.REWRITE
                    refreshSubscriptionRuleIndexes(
                        isRewrite,
                        RuleScope.DNS
                    )
                }
                _message.value = getApplication<Application>().getString(R.string.subscription_deleted)
            } catch (e: Exception) {
                withContext(Dispatchers.IO) {
                    loadSubscriptionsIntoState()
                }
                val context = getApplication<Application>()
                _message.value = context.getString(
                    R.string.subscription_delete_failed,
                    localizedText(context, e.message ?: "")
                )
            } finally {
                deletingSubscriptionIds -= id
                _operationMessage.value = null
            }
        }
    }

    fun toggleSubscriptionEnabled(id: Long, enabled: Boolean) {
        _operationMessage.value = if (enabled) {
            "正在启用规则订阅..."
        } else {
            "正在禁用规则订阅..."
        }
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val subscription = AppDatabase.getInstance(getApplication<Application>()).subscriptionDao().byId(id)
                val result = subscriptionManager().setSubscriptionEnabled(id, enabled)
                if (result.isSuccess) {
                    val isRewrite = subscription?.kind == com.haoze.dnssr.data.entity.SubscriptionKind.REWRITE
                    refreshSubscriptionRuleIndexes(
                        isRewrite,
                        RuleScope.DNS
                    )
                    loadSubscriptionsIntoState()
                }
                withContext(Dispatchers.Main) {
                    _message.value = if (result.isSuccess) {
                        if (enabled) "已启用规则订阅" else "已禁用规则订阅"
                    } else {
                        localizedText(
                            getApplication<Application>(),
                            "切换失败：${localizedText(getApplication<Application>(), result.exceptionOrNull()?.message ?: "")}"
                        )
                    }
                }
            } finally {
                _operationMessage.value = null
            }
        }
    }

    fun clearMessage() {
        _message.value = null
    }

    private fun refreshSubscriptionRuleIndexes(isRewrite: Boolean, scope: RuleScope) {
        val context = getApplication<Application>()
        RuntimeDnsSettingsRefresher.refreshRuleIndexesIfRunning(context, refreshBlock = true, refreshAllow = true, refreshRewrite = true, scope = scope)
        RuntimeDnsSettingsRefresher.syncHttpsRequestRulesIfRunning(context)
    }

    private fun enqueueAndObserve(workId: java.util.UUID, pendingSubscriptionId: Long? = null) {
        viewModelScope.launch {
            WorkManager.getInstance(getApplication<Application>())
                .getWorkInfoByIdFlow(workId)
                .collectLatest { info ->
                    if (info?.state?.isFinished == true) {
                        pendingSubscriptionId?.let { id ->
                            _pendingSubscriptions.value = _pendingSubscriptions.value.filterNot { it.id == id }
                        }
                        val message = info.outputData.getString(RuleOperationScheduler.KEY_MESSAGE)
                        val success = info.outputData.getBoolean(RuleOperationScheduler.KEY_SUCCESS, false)
                        _message.value = if (success) message else "操作失败：$message"
                        loadSubscriptions()
                        return@collectLatest
                    }
                }
        }
    }

    private fun applyBackgroundWorkState(infos: List<WorkInfo>) {
        val active = infos.firstOrNull {
            it.state == WorkInfo.State.RUNNING || it.state == WorkInfo.State.ENQUEUED ||
                it.state == WorkInfo.State.BLOCKED
        }
        val type = active?.progress?.getString(RuleOperationScheduler.KEY_TYPE)
            ?.let { runCatching { RuleOperationType.valueOf(it) }.getOrNull() }
        val subscriptionOperation = type in setOf(
            RuleOperationType.ADD_SUBSCRIPTION,
            RuleOperationType.ADD_LOCAL_SUBSCRIPTION,
            RuleOperationType.EDIT_SUBSCRIPTION,
            RuleOperationType.UPDATE_SUBSCRIPTION,
            RuleOperationType.UPDATE_ALL_SUBSCRIPTIONS
        )
        _importing.value = active != null && subscriptionOperation
        val id = active?.progress?.getLong(RuleOperationScheduler.KEY_SUBSCRIPTION_ID, -1) ?: -1
        _importingSubscriptionId.value = id.takeIf { it >= 0 }
        _updatingSubscriptionId.value = _importingSubscriptionId.value
        _progress.value = active?.progress?.let {
            SubscriptionProgress(
                it.getInt(RuleOperationScheduler.KEY_CURRENT, -1),
                it.getInt(RuleOperationScheduler.KEY_TOTAL, 0)
            )
        } ?: SubscriptionProgress()
        _operationMessage.value = if (type == RuleOperationType.UPDATE_ALL_SUBSCRIPTIONS) {
            "正在更新所有规则订阅..."
        } else null
    }

    private suspend fun loadSubscriptionsIntoState() {
        val list = subscriptionManager().allSubscriptions()
        withContext(Dispatchers.Main) {
            _subscriptions.value = list
        }
        updateRuleBreakdowns(list)
    }

    private suspend fun updateRuleBreakdowns(subscriptions: List<SubscriptionEntity>) {
        val database = AppDatabase.getInstance(getApplication<Application>())
        val blockDao = database.blockRuleDao()
        val allowDao = database.allowRuleDao()
        val rewriteDao = database.rewriteRuleDao()
        val map = subscriptions.associate { sub ->
            val source = "sub_${sub.id}"
            val blockCount = blockDao.countBySourceForList(source)
            val allowCount = allowDao.countBySourceForList(source)
            val rewriteCount = rewriteDao.countBySourceForList(source)
            sub.id to SubscriptionRuleBreakdown(blockCount, allowCount, rewriteCount)
        }
        withContext(Dispatchers.Main) {
            _ruleBreakdowns.value = map
        }
    }

    private fun loadDnsImportCandidates() {
        viewModelScope.launch(Dispatchers.IO) {
            val candidates = AppDatabase.getInstance(getApplication<Application>()).subscriptionDao()
                .all()
                .filter {
                    it.sourceType == com.haoze.dnssr.data.entity.SubscriptionSourceType.REMOTE
                }
            withContext(Dispatchers.Main) {
                _dnsImportCandidates.value = candidates
            }
        }
    }
}
