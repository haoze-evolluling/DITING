package com.haoze.dnssr.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay

/** 返回滞后 [delayMillis] 的 [value] 副本，常用于搜索输入的防抖。 */
@Composable
fun rememberDebouncedValue(value: String, delayMillis: Long = 250): String {
    var debounced by remember { mutableStateOf(value) }
    LaunchedEffect(value) {
        delay(delayMillis)
        debounced = value
    }
    return debounced
}
