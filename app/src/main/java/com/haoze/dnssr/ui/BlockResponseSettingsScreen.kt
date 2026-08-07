package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.vpn.BlockResponseMode
import com.haoze.dnssr.vpn.DynamicBlockResponseConfig

@Composable
fun BlockResponseSettingsScreen(
    onBack: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    var responseMode by remember { mutableStateOf(AppSettings.getBlockResponseMode(context)) }
    var dynamicConfig by remember { mutableStateOf(AppSettings.getDynamicBlockResponseConfig(context)) }
    var showParameterDialog by remember { mutableStateOf(false) }

    fun saveDynamicConfig(next: DynamicBlockResponseConfig) {
        dynamicConfig = next
        AppSettings.setDynamicBlockResponseConfig(context, next)
        onRuntimeDnsSettingsChanged()
    }

    SettingsScaffold(title = localizedText("拦截响应"), onBack = onBack) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsGroupTitle(localizedText("固定响应"))
            SettingsSurfaceGroup(
                content = BlockResponseMode.values().map { mode ->
                    {
                        SettingsRadioItem(
                            title = mode.displayName,
                            subtitle = responseSubtitle(mode),
                            selected = responseMode == mode,
                            onClick = {
                                if (responseMode != mode) {
                                    responseMode = mode
                                    AppSettings.setBlockResponseMode(context, mode)
                                    onRuntimeDnsSettingsChanged()
                                }
                            }
                        )
                    }
                }
            )
            SettingsInfoText(localizedText("动态策略开启时会临时覆盖以上选择：先返回 NODATA，高频请求后返回 NXDOMAIN。"))

            SettingsGroupTitle(localizedText("动态策略"))
            SettingsSurfaceGroup(
                content = listOf {
                    SettingsSwitchItem(
                        title = localizedText("启用动态策略"),
                        subtitle = localizedText("同一域名的所有记录类型合并计数"),
                        checked = dynamicConfig.enabled,
                        onCheckedChange = { saveDynamicConfig(dynamicConfig.copy(enabled = it)) }
                    )
                }
            )
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                    title = localizedText("动态参数"),
                    subtitle = localizedText("${dynamicConfig.requestThreshold} 次 / ${dynamicConfig.windowSeconds} 秒 / 保持 ${dynamicConfig.nxDomainDurationSeconds} 秒"),
                    onClick = { showParameterDialog = true }
                    )
                )
            )
            SettingsInfoText(localizedText("正常客户端会缓存 NODATA 响应。动态策略主要用于持续重试或忽略负缓存的请求。"))
        }
    }

    if (showParameterDialog) {
        DynamicParametersDialog(
            config = dynamicConfig,
            onDismiss = { showParameterDialog = false },
            onSave = {
                saveDynamicConfig(it)
                showParameterDialog = false
            }
        )
    }
}

@Composable
private fun DynamicParametersDialog(
    config: DynamicBlockResponseConfig,
    onDismiss: () -> Unit,
    onSave: (DynamicBlockResponseConfig) -> Unit
) {
    var thresholdText by remember { mutableStateOf(config.requestThreshold.toString()) }
    var windowText by remember { mutableStateOf(config.windowSeconds.toString()) }
    var durationText by remember { mutableStateOf(config.nxDomainDurationSeconds.toString()) }
    var error by remember { mutableStateOf<String?>(null) }

    fun save() {
        val threshold = thresholdText.toIntOrNull()
        val window = windowText.toIntOrNull()
        val duration = durationText.toIntOrNull()
        error = when {
            threshold == null || threshold !in DynamicBlockResponseConfig.MIN_REQUEST_THRESHOLD..DynamicBlockResponseConfig.MAX_REQUEST_THRESHOLD ->
                "请求次数需在 ${DynamicBlockResponseConfig.MIN_REQUEST_THRESHOLD}-${DynamicBlockResponseConfig.MAX_REQUEST_THRESHOLD} 之间"
            window == null || window !in DynamicBlockResponseConfig.MIN_WINDOW_SECONDS..DynamicBlockResponseConfig.MAX_WINDOW_SECONDS ->
                "统计窗口需在 ${DynamicBlockResponseConfig.MIN_WINDOW_SECONDS}-${DynamicBlockResponseConfig.MAX_WINDOW_SECONDS} 秒之间"
            duration == null || duration !in DynamicBlockResponseConfig.MIN_NXDOMAIN_DURATION_SECONDS..DynamicBlockResponseConfig.MAX_NXDOMAIN_DURATION_SECONDS ->
                "保持时长需在 ${DynamicBlockResponseConfig.MIN_NXDOMAIN_DURATION_SECONDS}-${DynamicBlockResponseConfig.MAX_NXDOMAIN_DURATION_SECONDS} 秒之间"
            else -> null
        }
        if (error == null) {
            onSave(
                config.copy(
                    requestThreshold = threshold!!,
                    windowSeconds = window!!,
                    nxDomainDurationSeconds = duration!!
                )
            )
        }
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("动态参数")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                DynamicParameterField(
                    label = localizedText("请求次数"),
                    value = thresholdText,
                    supportingText = localizedText("${DynamicBlockResponseConfig.MIN_REQUEST_THRESHOLD}-${DynamicBlockResponseConfig.MAX_REQUEST_THRESHOLD} 次；第 N+1 次开始升级"),
                    onValueChange = { thresholdText = it; error = null }
                )
                DynamicParameterField(
                    label = localizedText("统计窗口（秒）"),
                    value = windowText,
                    supportingText = localizedText("${DynamicBlockResponseConfig.MIN_WINDOW_SECONDS}-${DynamicBlockResponseConfig.MAX_WINDOW_SECONDS} 秒"),
                    onValueChange = { windowText = it; error = null }
                )
                DynamicParameterField(
                    label = localizedText("NXDOMAIN 保持时长（秒）"),
                    value = durationText,
                    supportingText = localizedText("${DynamicBlockResponseConfig.MIN_NXDOMAIN_DURATION_SECONDS}-${DynamicBlockResponseConfig.MAX_NXDOMAIN_DURATION_SECONDS} 秒；首次升级起固定计时"),
                    onValueChange = { durationText = it; error = null }
                )
                error?.let { Text(localizedText(it)) }
            }
        },
        confirmButton = {
            TextButton(onClick = ::save) { Text(localizedText("保存")) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(localizedText("取消")) }
        }
    )
}

@Composable
private fun DynamicParameterField(
    label: String,
    value: String,
    supportingText: String,
    onValueChange: (String) -> Unit
) {
    OutlinedTextField(
        value = value,
        onValueChange = { input -> onValueChange(input.filter(Char::isDigit)) },
        label = { Text(label) },
        supportingText = { Text(supportingText) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(
            keyboardType = KeyboardType.Number,
            imeAction = ImeAction.Done
        ),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    )
}

private fun responseSubtitle(mode: BlockResponseMode): String = when (mode) {
    BlockResponseMode.NXDOMAIN -> "返回域名不存在，并提供 5 分钟负缓存以减少重复查询"
    BlockResponseMode.NODATA -> "返回域名存在但没有该记录，并提供 5 分钟负缓存"
    BlockResponseMode.REFUSED -> "返回服务器拒绝该查询，不提供缓存记录"
    BlockResponseMode.ZERO_ADDRESS -> "A 返回 0.0.0.0，AAAA 返回 ::，其他类型返回空结果"
}
