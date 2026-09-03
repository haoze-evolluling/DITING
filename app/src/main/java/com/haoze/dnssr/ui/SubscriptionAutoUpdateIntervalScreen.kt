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
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateScheduler
import com.haoze.dnssr.vpn.SubscriptionAutoUpdateSettings
import kotlinx.coroutines.launch

@Composable
fun SubscriptionAutoUpdateIntervalScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    val groups by AppDatabase.getInstance(context).subscriptionGroupDao()
        .observeAll()
        .collectAsStateWithLifecycle(initialValue = emptyList())
    val coroutineScope = rememberCoroutineScope()
    var intervalHours by remember {
        mutableIntStateOf(SubscriptionAutoUpdateSettings.intervalHours(context))
    }
    var autoUpdateEnabled by remember {
        mutableStateOf(SubscriptionAutoUpdateSettings.isEnabled(context))
    }
    var showCustomDialog by remember { mutableStateOf(false) }
    var customHours by remember { mutableStateOf("") }
    var customError by remember { mutableStateOf<String?>(null) }

    fun saveInterval(hours: Int) {
        intervalHours = hours
        SubscriptionAutoUpdateSettings.save(
            context,
            SubscriptionAutoUpdateSettings.isEnabled(context),
            hours
        )
        SubscriptionAutoUpdateScheduler.sync(context)
    }

    fun openCustomDialog() {
        customHours = intervalHours.toString()
        customError = null
        showCustomDialog = true
    }

    fun closeCustomDialog() {
        showCustomDialog = false
        customError = null
    }

    SettingsScaffold(title = localizedText("自动更新设置"), onBack = onBack) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
        SettingsGroupTitle(localizedText("自动更新"))
            SettingsSurfaceGroup(content = listOf {
                SettingsSwitchItem(
                    title = localizedText("自动更新规则订阅"),
                    subtitle = localizedText("在后台定期更新所有网络订阅，实际执行时间可能受系统调度影响"),
                    checked = autoUpdateEnabled,
                    onCheckedChange = { enabled ->
                        autoUpdateEnabled = enabled
                        SubscriptionAutoUpdateSettings.save(context, enabled, intervalHours)
                        SubscriptionAutoUpdateScheduler.sync(context)
                    }
                )
            })

        SettingsGroupTitle(localizedText("自动更新时间"))
            SettingsSurfaceGroup(
                content = SubscriptionAutoUpdateSettings.intervals.map { hours ->
                    {
                        SettingsRadioItem(
                    title = localizedText("每 $hours 小时"),
                            selected = intervalHours == hours,
                            onClick = {
                                customError = null
                                saveInterval(hours)
                            }
                        )
                    }
                }
            )
        SettingsInfoText(localizedText("系统会在后台按此频率检查网络规则订阅，实际执行时间可能受系统调度影响。"))

        SettingsGroupTitle(localizedText("分组自动更新"))
            if (groups.isEmpty()) {
            SettingsInfoText(localizedText("暂无分组"))
            } else {
                SettingsSurfaceGroup(
                    content = groups.map { group ->
                        {
                            SettingsSwitchItem(
                                title = group.name,
                                checked = group.autoUpdateEnabled,
                                onCheckedChange = { enabled ->
                                    coroutineScope.launch {
                                        AppDatabase.getInstance(context).subscriptionGroupDao()
                                            .setAutoUpdateEnabled(group.id, enabled)
                                    }
                                }
                            )
                        }
                    }
                )
            }
            SettingsInfoText(localizedText("仅会自动更新已开启的分组中的网络订阅。"))

        SettingsGroupTitle(localizedText("自定义间隔"))
            SettingsNavigationGroup(
                items = listOf(
                    SettingsNavigationItemData(
                    title = localizedText("自定义更新时间"),
                    subtitle = localizedText("输入 1 至 168 小时之间的更新时间"),
                    value = if (intervalHours !in SubscriptionAutoUpdateSettings.intervals) {
                        localizedText("每 $intervalHours 小时")
                    } else {
                        null
                    },
                    onClick = ::openCustomDialog
                    )
                )
            )
        }
    }

    if (showCustomDialog) {
        AlertDialog(
            onDismissRequest = ::closeCustomDialog,
            title = { Text(localizedText("自定义更新时间")) },
            text = {
                OutlinedTextField(
                    value = customHours,
                    onValueChange = {
                        customHours = it
                        customError = null
                    },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(localizedText("小时")) },
                    supportingText = {
                        Text(customError?.let { localizedText(it) } ?: localizedText("可设置 1 至 168 小时"))
                    },
                    isError = customError != null,
                    singleLine = true,
                    shape = SettingsCornerShape,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number)
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val hours = customHours.trim().toIntOrNull()
                        if (
                            hours == null ||
                            hours !in SubscriptionAutoUpdateSettings.MIN_INTERVAL_HOURS..SubscriptionAutoUpdateSettings.MAX_INTERVAL_HOURS
                        ) {
                            customError = "请输入 1 至 168 之间的小时数"
                        } else {
                            saveInterval(hours)
                            closeCustomDialog()
                        }
                    }
                ) {
                    Text(localizedText("确定"))
                }
            },
            dismissButton = {
                TextButton(onClick = ::closeCustomDialog) {
                    Text(localizedText("取消"))
                }
            }
        )
    }
}
