package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.paging.Pager
import androidx.paging.PagingConfig
import androidx.paging.PagingData
import androidx.paging.cachedIn
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.DnsCacheQueryParams
import com.haoze.dnssr.data.entity.DnsCacheEntity
import com.haoze.dnssr.data.repository.DnsCacheRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
class DnsCacheViewModel(application: Application) : AndroidViewModel(application) {
    private val repository = DnsCacheRepository(AppDatabase.getInstance(application).dnsCacheDao())
    private val _activated = MutableStateFlow(false)
    private val _params = MutableStateFlow(DnsCacheQueryParams("", System.currentTimeMillis()))
    private val _nowMillis = MutableStateFlow(System.currentTimeMillis())
    private var refreshJob: Job? = null
    val params: StateFlow<DnsCacheQueryParams> = _params.asStateFlow()
    val nowMillis: StateFlow<Long> = _nowMillis.asStateFlow()

    fun activate() { _activated.value = true }

    val entries: Flow<PagingData<DnsCacheEntity>> = _activated
        .filter { it }
        .flatMapLatest {
            _params
                .debounce { if (it.query.isBlank()) 0L else 300L }
                .flatMapLatest { params ->
                    Pager(
                        config = PagingConfig(
                            pageSize = DnsCacheRepository.PAGE_SIZE,
                            enablePlaceholders = false
                        ),
                        pagingSourceFactory = { repository.cachePagingSource(params) }
                    ).flow
                }
        }
        .cachedIn(viewModelScope)

    fun onSearchQueryChange(query: String) {
        _params.update { it.copy(query = query, asOfMillis = System.currentTimeMillis()) }
    }

    fun updateClock() {
        _nowMillis.value = System.currentTimeMillis()
    }

    fun refreshCacheList() {
        if (refreshJob?.isActive == true) return
        refreshJob = viewModelScope.launch(Dispatchers.IO) {
            val now = System.currentTimeMillis()
            repository.deleteExpired(now)
            _nowMillis.value = now
            _params.update { it.copy(asOfMillis = now) }
        }
    }
}
