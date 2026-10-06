package com.haoze.diting.dnsmode.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.diting.dnsmode.backend.DnsModeManager
import com.haoze.diting.dnsmode.backend.DnsModePreferences
import com.haoze.diting.dnsmode.model.DnsServiceStatus
import com.haoze.diting.dnsmode.viewmodel.DnsMainViewModel
import com.haoze.diting.permission.BatteryOptimizationHelper

/**
 * Host composable for Server/DNS mode embedded directly in MainActivity.
 * Eliminates cross-activity transitions and encapsulates battery optimization handling.
 */
@Composable
fun DnsModeHost(
    onSelectMode: () -> Unit,
    resetToHomeTrigger: Long = 0L,
    modifier: Modifier = Modifier,
    onSwitchToNormalMode: () -> Unit = {},
    viewModel: DnsMainViewModel = viewModel()
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val batteryState = BatteryOptimizationHelper.rememberBatteryOptimizationState()

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                if (DnsModePreferences.isServiceActive(context) &&
                    DnsModeManager.status.value == DnsServiceStatus.STOPPED
                ) {
                    DnsModeManager.startService(context)
                }
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    DnsMainScreen(
        viewModel = viewModel,
        batteryOptimizationIgnored = batteryState.isIgnored,
        onRequestIgnoreBatteryOptimization = batteryState.requestIgnore,
        onSwitchToNormalMode = onSwitchToNormalMode,
        onSelectMode = onSelectMode,
        resetToHomeTrigger = resetToHomeTrigger
    )
}
