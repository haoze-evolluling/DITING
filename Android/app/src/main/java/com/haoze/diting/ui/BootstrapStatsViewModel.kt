package com.haoze.diting.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import com.haoze.diting.data.BootstrapOverallStats
import com.haoze.diting.data.BootstrapStats
import com.haoze.diting.data.BootstrapStatsRange
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.repository.BootstrapLogRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class BootstrapStatsViewModel @JvmOverloads constructor(
    application: Application,
    dataset: RuleDataset = RuleDataset.NORMAL
) : AndroidViewModel(application) {
    private val repository = BootstrapLogRepository(
        application,
        RuleDatabases.runtimeForDataset(application, dataset).bootstrapLogDao()
    )

    private val _range = MutableStateFlow(BootstrapStatsRange.TODAY)
    val range: StateFlow<BootstrapStatsRange> = _range.asStateFlow()

    private val _stats = MutableStateFlow(
        BootstrapStats(BootstrapOverallStats(0, 0, 0, 0.0, 0), emptyList())
    )
    val stats: StateFlow<BootstrapStats> = _stats.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    fun activate() {
        refresh()
    }

    fun setRange(range: BootstrapStatsRange) {
        if (_range.value == range) return
        _range.value = range
        refresh()
    }

    fun refresh() {
        viewModelScope.launch(Dispatchers.IO) {
            _loading.value = true
            _stats.value = repository.stats(_range.value)
            _loading.value = false
        }
    }

    companion object {
        fun factory(
            application: Application,
            dataset: RuleDataset = RuleDataset.NORMAL
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T {
                return BootstrapStatsViewModel(application, dataset) as T
            }
        }
    }
}
