package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.repository.RequestLogRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class RequestLogUiState(
    val items: List<RequestLogItem> = emptyList(),
    val source: RequestSource = RequestSource.ALL,
    val status: RequestStatus = RequestStatus.ALL,
    val query: String = "",
    val searching: Boolean = false,
    val loading: Boolean = false,
    val hasMore: Boolean = true,
    val error: String? = null
)

class RequestLogViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = RequestLogRepository(
        AppDatabase.getInstance(application).dnsLogDao(),
        AppDatabase.getInstance(application).httpRequestLogDao()
    )
    private val _state = MutableStateFlow(RequestLogUiState())
    val state: StateFlow<RequestLogUiState> = _state.asStateFlow()
    private var limit = 50

    init { refresh() }

    fun refresh() {
        limit = 50
        load()
    }

    fun loadMore() {
        if (_state.value.loading || !_state.value.hasMore) return
        limit += 50
        load()
    }

    fun setSource(source: RequestSource) { _state.value = _state.value.copy(source = source) }
    fun setStatus(status: RequestStatus) { _state.value = _state.value.copy(status = status) }
    fun setQuery(query: String) { _state.value = _state.value.copy(query = query) }
    fun setSearching(value: Boolean) { _state.value = _state.value.copy(searching = value) }

    private fun load() {
        viewModelScope.launch(Dispatchers.IO) {
            _state.value = _state.value.copy(loading = true, error = null)
            runCatching { repository.load(limit) }.onSuccess { batch ->
                val items = (batch.dns.map(::dnsRequestItem) + batch.http.map(::httpRequestItem))
                    .sortedByDescending { it.timestamp }
                _state.value = _state.value.copy(items = items, loading = false, hasMore = batch.hasMore)
            }.onFailure { error ->
                _state.value = _state.value.copy(loading = false, error = error.message ?: "加载失败")
            }
        }
    }
}
