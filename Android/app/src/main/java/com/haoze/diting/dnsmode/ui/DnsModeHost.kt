package com.haoze.diting.dnsmode.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
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

/**
 * Host composable for Server/DNS mode embedded directly in MainActivity.
 * Eliminates cross-activity transitions and encapsulates battery optimization handling.
 */
@Composable
fun DnsModeHost(
    onSwitchToNormalMode: () -> Unit,
    onSelectMode: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: DnsMainViewModel = viewModel()
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var batteryOptimizationIgnored by remember {
        mutableStateOf(isBatteryOptimizationIgnored(context))
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                batteryOptimizationIgnored = isBatteryOptimizationIgnored(context)
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
        batteryOptimizationIgnored = batteryOptimizationIgnored,
        onRequestIgnoreBatteryOptimization = {
            requestIgnoreBatteryOptimization(context)
        },
        onSwitchToNormalMode = onSwitchToNormalMode,
        onSelectMode = onSelectMode
    )
}

private fun isBatteryOptimizationIgnored(context: Context): Boolean {
    val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
    return powerManager?.isIgnoringBatteryOptimizations(context.packageName) ?: false
}

private fun requestIgnoreBatteryOptimization(context: Context) {
    val requestIntent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
        data = android.net.Uri.parse("package:${context.packageName}")
    }
    try {
        context.startActivity(requestIntent)
    } catch (_: ActivityNotFoundException) {
        runCatching {
            context.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }
}
