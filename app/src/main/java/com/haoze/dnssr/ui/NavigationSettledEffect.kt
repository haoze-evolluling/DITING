package com.haoze.dnssr.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.flow.first

@Composable
internal fun NavigationSettledEffect(
    key: Any? = Unit,
    block: suspend () -> Unit
) {
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var hasRun by rememberSaveable(key) { mutableStateOf(false) }
    LaunchedEffect(lifecycle, key) {
        if (hasRun) return@LaunchedEffect
        lifecycle.currentStateFlow.first { it == Lifecycle.State.RESUMED }
        hasRun = true
        block()
    }
}
