package com.haoze.dnssr.update

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * 宿主 Activity 共享的应用内更新状态与流程（检查 / 下载 / 安装 / 通知），
 * 统一 MainActivity 与 SettingsRouteActivity 的重复实现。
 */
class AppUpdateHost(private val activity: ComponentActivity) {

    var state by mutableStateOf(AppUpdateUiState())
        private set
    var dismissedVersion by mutableStateOf("")
    private var downloadJob: Job? = null
    private var downloadGeneration = 0L
    private val manager by lazy { AppUpdateManager(activity.applicationContext) }
    private val notifier by lazy { AppUpdateNotifier(activity.applicationContext) }

    fun checkForUpdate(manual: Boolean) {
        if (state.checking) return
        if (manual) dismissedVersion = ""
        state = state.copy(
            checking = true,
            error = "",
            message = if (manual) "正在检查 GitHub Release" else state.message,
        )
        activity.lifecycleScope.launch {
            try {
                val update = manager.checkForUpdate()
                val downloadState = update?.let { manager.refreshDownloadState(it) }
                state = AppUpdateUiState(
                    availableUpdate = update,
                    downloadState = downloadState ?: state.downloadState,
                    message = if (update == null) "当前已是最新版本。" else "发现 ${update.version} 新版本。",
                )
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                state = state.copy(
                    checking = false,
                    error = if (manual) error.message ?: "检查更新失败。" else "",
                    message = if (manual) "" else state.message,
                )
            }
        }
    }

    fun downloadUpdate() {
        val update = state.availableUpdate ?: return
        val status = state.downloadState.status.takeIf { state.downloadState.version == update.version }
        if (status == AppUpdateDownloadStatus.Downloading) return
        if (status == AppUpdateDownloadStatus.Downloaded) {
            if (!manager.installDownloadedUpdate(update)) {
                state = state.copy(
                    downloadState = AppUpdateDownloadState(version = update.version),
                    error = "安装包不存在或无法打开，请重新下载。",
                )
            }
            return
        }
        downloadJob?.cancel()
        notifier.clear()
        val generation = ++downloadGeneration
        downloadJob = activity.lifecycleScope.launch {
            try {
                state = state.copy(
                    downloadState = AppUpdateDownloadState(
                        version = update.version,
                        status = AppUpdateDownloadStatus.Downloading,
                    ),
                    error = "",
                )
                notifier.showProgress(update, 0L, -1L)
                val downloadState = manager.download(update) { downloadedBytes, totalBytes ->
                    activity.runOnUiThread {
                        if (
                            generation == downloadGeneration &&
                            state.downloadState.status == AppUpdateDownloadStatus.Downloading
                        ) {
                            state = state.copy(
                                downloadState = AppUpdateDownloadState(
                                    version = update.version,
                                    status = AppUpdateDownloadStatus.Downloading,
                                    downloadedBytes = downloadedBytes,
                                    totalBytes = totalBytes,
                                )
                            )
                            notifier.showProgress(update, downloadedBytes, totalBytes)
                        }
                    }
                }
                if (generation != downloadGeneration) return@launch
                state = state.copy(
                    downloadState = downloadState,
                    error = if (downloadState.status == AppUpdateDownloadStatus.Failed) "更新包下载失败，请重试。" else "",
                    message = if (downloadState.status == AppUpdateDownloadStatus.Downloaded) "下载完成，请点击安装。" else state.message,
                )
                if (downloadState.status == AppUpdateDownloadStatus.Downloaded) {
                    notifier.showCompleted(update)
                } else {
                    notifier.clear()
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Throwable) {
                notifier.clear()
                state = state.copy(error = error.message ?: "无法开始下载更新。")
            }
        }
    }

    fun refreshDownloadState() {
        val update = state.availableUpdate ?: return
        activity.lifecycleScope.launch {
            runCatching { manager.refreshDownloadState(update) }
                .onSuccess { downloadState -> state = state.copy(downloadState = downloadState) }
        }
    }

    /** 宿主进入后台时取消进行中的下载并清理通知。 */
    fun cancelActiveDownload() {
        if (state.downloadState.status == AppUpdateDownloadStatus.Downloading) {
            downloadGeneration++
            downloadJob?.cancel()
            downloadJob = null
            notifier.clear()
            state = state.copy(
                downloadState = AppUpdateDownloadState(version = state.downloadState.version)
            )
        }
    }
}
