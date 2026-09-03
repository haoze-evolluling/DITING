package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.BuildConfig
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.ui.components.SettingsTextItem
import com.haoze.dnssr.update.AppUpdateDownloadStatus
import com.haoze.dnssr.update.AppUpdateUiState

@Composable
fun AppUpdateScreen(
    state: AppUpdateUiState,
    onBack: () -> Unit,
    onCheck: () -> Unit,
    onDownload: () -> Unit,
    onJoinQqGroup: () -> Unit,
    startupUpdateCheckDisabled: Boolean,
    onStartupUpdateCheckDisabledChange: (Boolean) -> Unit,
) {
    val update = state.availableUpdate
    val downloadStatus = state.downloadState.status.takeIf { state.downloadState.version == update?.version }
        ?: AppUpdateDownloadStatus.Idle
    SettingsScaffold(title = localizedText("更新与支持"), onBack = onBack) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SettingsSurfaceGroup(
                content = buildList {
                    add {
                        SettingsTextItem(
                            title = localizedText("当前版本"),
                            subtitle = BuildConfig.VERSION_NAME,
                            enabled = false,
                            onClick = {},
                        )
                    }
                    add {
                        SettingsTextItem(
                            title = localizedText("检查更新"),
                            subtitle = updateStatusText(state, downloadStatus),
                            enabled = !state.checking,
                            onClick = onCheck,
                        )
                    }
                    add {
                        SettingsSwitchItem(
                            title = localizedText("关闭启动时检查更新"),
                            subtitle = if (startupUpdateCheckDisabled) {
                                localizedText("应用启动时不自动检查，可随时手动检查")
                            } else {
                                localizedText("应用启动时自动检查新版本")
                            },
                            checked = startupUpdateCheckDisabled,
                            onCheckedChange = onStartupUpdateCheckDisabledChange,
                        )
                    }
                    add {
                        SettingsTextItem(
                            title = localizedText("加入 QQ 群"),
                            subtitle = localizedText("交流群：1090225658 （入群答案：造梦）"),
                            onClick = onJoinQqGroup,
                        )
                    }
                    if (update != null) {
                        add {
                            SettingsTextItem(
                                title = (if (downloadStatus == AppUpdateDownloadStatus.Downloaded) localizedText("安装") else localizedText("下载")) + " ${update.version}",
                                subtitle = downloadActionText(downloadStatus),
                                enabled = downloadStatus != AppUpdateDownloadStatus.Downloading,
                                onClick = onDownload,
                            )
                        }
                    }
                }
            )
            if (state.error.isNotBlank()) {
                Text(
                    text = localizedText(state.error),
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(horizontal = 32.dp),
                )
            }
        }
    }
}

@Composable
private fun updateStatusText(state: AppUpdateUiState, downloadStatus: AppUpdateDownloadStatus): String = when {
    state.checking -> localizedText("正在检查 GitHub Release")
    state.availableUpdate != null -> localizedText("发现新版本") + " ${state.availableUpdate.version}，${downloadActionText(downloadStatus)}"
    state.error.isNotBlank() -> localizedText("检查失败，点击重试")
    state.message.isNotBlank() -> localizedText(state.message)
    else -> localizedText("检查 GitHub Release 中的最新版本")
}

@Composable
private fun downloadActionText(status: AppUpdateDownloadStatus): String = when (status) {
    AppUpdateDownloadStatus.Idle -> localizedText("可下载")
    AppUpdateDownloadStatus.Downloading -> localizedText("下载中")
    AppUpdateDownloadStatus.Downloaded -> localizedText("安装包已下载，点击安装")
    AppUpdateDownloadStatus.Failed -> localizedText("上次下载失败，点击重试")
}
