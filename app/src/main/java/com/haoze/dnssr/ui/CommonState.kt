package com.haoze.dnssr.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay

/** Returns a copy of [value] lagging by [delayMillis]; commonly used to debounce search input. */
@Composable
fun rememberDebouncedValue(value: String, delayMillis: Long = 250): String {
    var debounced by remember { mutableStateOf(value) }
    LaunchedEffect(value) {
        delay(delayMillis)
        debounced = value
    }
    return debounced
}
