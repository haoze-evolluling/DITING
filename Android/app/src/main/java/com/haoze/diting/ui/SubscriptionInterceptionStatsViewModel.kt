package com.haoze.diting.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.SubscriptionInterceptionStatsRange
import com.haoze.diting.data.repository.DnsLogRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class SubscriptionInterceptionStatItem(
    val subscriptionId: Long,
    val name: String,
    val enabled: Boolean,
    val deleted: Boolean,
    val hits: Int,
    val rate: Double
)

class SubscriptionInterceptionStatsViewModel(
    application: Application,
    val dataset: RuleDataset = RuleDataset.NORMAL
) : AndroidViewModel(application) {

    private val isNormal = dataset == RuleDataset.NORMAL
    private val database = RuleDatabases.forDataset(application, dataset)
    private val runtimeDb = RuleDatabases.runtimeForDataset(application, dataset)
    private val normalDatabase = if (isNormal) AppDatabase.getInstance(application) else null
    private val repository = DnsLogRepository(
        runtimeDb.dnsLogDao(),
        if (isNormal) normalDatabase?.httpRequestLogDao() else null
    )

    private val _range = MutableStateFlow(SubscriptionInterceptionStatsRange.TODAY)
    val range: StateFlow<SubscriptionInterceptionStatsRange> = _range.asStateFlow()

    private val _totalRequests = MutableStateFlow(0)
    val totalRequests: StateFlow<Int> = _totalRequests.asStateFlow()

    private val _items = MutableStateFlow<List<SubscriptionInterceptionStatItem>>(emptyList())
    val items: StateFlow<List<SubscriptionInterceptionStatItem>> = _items.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    fun setRange(range: SubscriptionInterceptionStatsRange) {
        if (_range.value == range) return
        _range.value = range
        refresh()
    }

    fun refresh() {
        viewModelScope.launch(Dispatchers.IO) {
            _loading.value = true
            try {
                val stats = repository.subscriptionInterceptionStats(_range.value)
                val subscriptions = database.subscriptionDao().all()
                val byId = subscriptions.associateBy { it.id }
                val ids = (byId.keys + stats.hitsBySubscriptionId.keys).toSortedSet()
                val items = ids.map { id ->
                    val subscription = byId[id]
                    val hits = stats.hitsBySubscriptionId[id] ?: 0
                    SubscriptionInterceptionStatItem(
                        subscriptionId = id,
                        name = subscription?.name ?: "已删除订阅 #$id",
                        enabled = subscription?.enabled ?: false,
                        deleted = subscription == null,
                        hits = hits,
                        rate = if (stats.totalRequests == 0) 0.0 else hits.toDouble() / stats.totalRequests
                    )
                }.sortedWith(compareByDescending<SubscriptionInterceptionStatItem> { it.hits }.thenBy { it.name })
                withContext(Dispatchers.Main) {
                    _totalRequests.value = stats.totalRequests
                    _items.value = items
                }
            } finally {
                _loading.value = false
            }
        }
    }

    companion object {
        fun factory(
            application: Application,
            dataset: RuleDataset = RuleDataset.NORMAL
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                return SubscriptionInterceptionStatsViewModel(application, dataset) as T
            }
        }
    }
}
