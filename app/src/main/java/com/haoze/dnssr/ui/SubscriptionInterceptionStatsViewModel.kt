package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.SubscriptionInterceptionStatsRange
import com.haoze.dnssr.data.entity.SubscriptionKind
import com.haoze.dnssr.data.repository.DnsLogRepository
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

class SubscriptionInterceptionStatsViewModel(application: Application) : AndroidViewModel(application) {

    private val database = AppDatabase.getInstance(application)
    private val repository = DnsLogRepository(database.dnsLogDao(), database.httpRequestLogDao())

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
                val subscriptions = database.subscriptionDao().allByKind(SubscriptionKind.BLOCK)
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
}
