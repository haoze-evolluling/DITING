package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppDialogButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
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
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.ui.settings.RuleSettingsAccess
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsRadioItem
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSectionSpacing
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.core.rule.SubscriptionAutoUpdateScheduler
import com.haoze.diting.core.rule.SubscriptionAutoUpdateSettings
import kotlinx.coroutines.launch

@Composable
fun SubscriptionAutoUpdateIntervalScreen(
    onBack: () -> Unit,
    dataset: RuleDataset = RuleDataset.NORMAL
) {
    val context = LocalContext.current
    val settings = RuleSettingsAccess(dataset)
    val groups by RuleDatabases.forDataset(context, dataset).subscriptionGroupDao()
        .observeAll()
        .collectAsStateWithLifecycle(initialValue = emptyList())
    val coroutineScope = rememberCoroutineScope()
    var intervalHours by remember {
        mutableIntStateOf(settings.autoUpdateIntervalHours(context))
    }
    var autoUpdateEnabled by remember {
        mutableStateOf(settings.autoUpdateEnabled(context))
    }
    var showCustomDialog by remember { mutableStateOf(false) }
    var customHours by remember { mutableStateOf("") }
    var customError by remember { mutableStateOf<String?>(null) }

    // When the master switch is off, the update frequency and group switches are disabled as dependent settings
    val autoUpdateControlsEnabled = autoUpdateEnabled
    val isCustomInterval = intervalHours !in SubscriptionAutoUpdateSettings.intervals

    fun saveInterval(hours: Int) {
        intervalHours = hours
        settings.saveAutoUpdate(
            context,
            settings.autoUpdateEnabled(context),
            hours
        )
        SubscriptionAutoUpdateScheduler.sync(context, dataset)
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
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(SettingsSectionSpacing)
        ) {
            item { SettingsGroupTitle(localizedText("自动更新")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        SettingsSwitchItem(
                            title = localizedText("自动更新规则订阅"),
                            subtitle = localizedText("在后台定期更新所有网络订阅，实际执行时间可能受系统调度影响"),
                            checked = autoUpdateEnabled,
                            onCheckedChange = { enabled ->
                                autoUpdateEnabled = enabled
                                settings.saveAutoUpdate(context, enabled, intervalHours)
                                SubscriptionAutoUpdateScheduler.sync(context, dataset)
                            }
                        )
                    }
                )
            }

            item { SettingsGroupTitle(localizedText("更新频率")) }
            item {
                val presetOptions: List<@Composable () -> Unit> =
                    SubscriptionAutoUpdateSettings.intervals.map { hours ->
                        {
                            SettingsRadioItem(
                                title = localizedText("每 $hours 小时"),
                                selected = intervalHours == hours,
                                enabled = autoUpdateControlsEnabled,
                                onClick = {
                                    customError = null
                                    saveInterval(hours)
                                }
                            )
                        }
                    }
                val customOption: @Composable () -> Unit = {
                    SettingsRadioItem(
                        title = localizedText("自定义更新时间"),
                        subtitle = if (isCustomInterval) {
                            localizedText("每 $intervalHours 小时")
                        } else {
                            localizedText("输入 1 至 168 小时之间的更新时间")
                        },
                        selected = isCustomInterval,
                        enabled = autoUpdateControlsEnabled,
                        onClick = ::openCustomDialog
                    )
                }
                SettingsSurfaceGroup(content = presetOptions + customOption)
            }
            item {
                SettingsInfoText(
                    localizedText("系统会在后台按此频率检查网络规则订阅，实际执行时间可能受系统调度影响。")
                )
            }

            item { SettingsGroupTitle(localizedText("分组自动更新")) }
            if (groups.isEmpty()) {
                item {
                    SettingsSurfaceGroup(
                        content = listOf {
                            SettingsItem(title = localizedText("暂无分组"))
                        }
                    )
                }
            } else {
                item {
                    SettingsSurfaceGroup(
                        content = groups.map { group ->
                            {
                                SettingsSwitchItem(
                                    title = group.name,
                                    checked = group.autoUpdateEnabled,
                                    enabled = autoUpdateControlsEnabled,
                                    onCheckedChange = { enabled ->
                                        coroutineScope.launch {
                                            RuleDatabases.forDataset(context, dataset).subscriptionGroupDao()
                                                .setAutoUpdateEnabled(group.id, enabled)
                                        }
                                    }
                                )
                            }
                        }
                    )
                }
            }
            item {
                SettingsInfoText(localizedText("仅会自动更新已开启的分组中的网络订阅。"))
            }

            item { Spacer(Modifier.height(8.dp)) }
        }
    }

    if (showCustomDialog) {
        AppAlertDialog(
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
                    label = { Text(localizedText("更新间隔")) },
                    suffix = { Text(localizedText("小时")) },
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
                AppDialogButton(
                    label = "确定",
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
                )
            },
            dismissButton = {
                AppDialogButton(
                    label = "取消",
                    onClick = ::closeCustomDialog
                )
            }
        )
    }
}
