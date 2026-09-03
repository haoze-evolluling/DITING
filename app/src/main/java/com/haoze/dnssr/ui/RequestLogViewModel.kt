package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.RequestSource
import com.haoze.dnssr.data.RequestStatus
import com.haoze.dnssr.data.repository.RequestLogRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
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
    private var searchJob: Job? = null
    private var loadJob: Job? = null

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

    fun setSource(source: RequestSource) {
        if (_state.value.source == source) return
        _state.value = _state.value.copy(source = source)
        refresh()
    }

    fun setStatus(status: RequestStatus) {
        if (_state.value.status == status) return
        _state.value = _state.value.copy(status = status)
        refresh()
    }

    fun setQuery(query: String) {
        _state.value = _state.value.copy(query = query)
        searchJob?.cancel()
        searchJob = viewModelScope.launch {
            if (query.isNotBlank()) delay(250)
            limit = 50
            load()
        }
    }

    fun setSearching(value: Boolean) {
        _state.value = _state.value.copy(searching = value)
        if (!value && _state.value.query.isNotEmpty()) {
            setQuery("")
        }
    }

    private fun load() {
        loadJob?.cancel()
        val currentSource = _state.value.source
        val currentStatus = _state.value.status
        val currentQuery = _state.value.query
        val currentLimit = limit

        loadJob = viewModelScope.launch(Dispatchers.IO) {
            _state.value = _state.value.copy(loading = true, error = null)
            runCatching {
                repository.load(
                    limit = currentLimit,
                    source = currentSource,
                    status = currentStatus,
                    query = currentQuery
                )
            }.onSuccess { batch ->
                val items = (batch.dns.map(::dnsRequestItem) + batch.http.map(::httpRequestItem))
                    .sortedByDescending { it.timestamp }
                    .take(currentLimit)
                _state.value = _state.value.copy(
                    items = items,
                    loading = false,
                    hasMore = batch.hasMore
                )
            }.onFailure { error ->
                _state.value = _state.value.copy(
                    loading = false,
                    error = error.message ?: "加载失败"
                )
            }
        }
    }
}
