package com.haoze.dnssr.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.RaceStats
import com.haoze.dnssr.data.RaceStatsRange
import com.haoze.dnssr.data.repository.RaceLogRepository
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

class RaceStatsViewModel(application: Application) : AndroidViewModel(application) {

    private val repository = RaceLogRepository(AppDatabase.getInstance(application).raceLogDao())

    private val _range = MutableStateFlow(RaceStatsRange.TODAY)
    val range: StateFlow<RaceStatsRange> = _range.asStateFlow()

    private val _stats = MutableStateFlow(RaceStats(emptyList(), emptyList(), emptyList()))
    val stats: StateFlow<RaceStats> = _stats.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()

    fun activate() {
        refresh()
    }

    fun setRange(range: RaceStatsRange) {
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
}
