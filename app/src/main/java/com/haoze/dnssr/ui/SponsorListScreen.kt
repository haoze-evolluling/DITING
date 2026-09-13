package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import kotlinx.coroutines.launch

@Composable
fun SponsorListScreen(
    onBack: () -> Unit,
    title: String = "赞助者名单"
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var configuration by remember { mutableStateOf<RecognitionMembersConfiguration?>(null) }
    var isConfigurationLoading by remember { mutableStateOf(true) }
    val sponsors = configuration?.sponsors.orEmpty()
    val avatarLoader = rememberRecognitionAvatarLoader(sponsors)
    var newestFirst by remember { mutableStateOf(false) }
    val displayedSponsors = if (newestFirst) sponsors.asReversed() else sponsors

    LaunchedEffect(context.applicationContext) {
        val cachedConfiguration = RecognitionMembersRepository.loadCached(context.applicationContext)
        configuration = cachedConfiguration
        if (cachedConfiguration != null) isConfigurationLoading = false
        runCatching { RecognitionMembersRepository.refresh(context.applicationContext) }
            .onFailure { error ->
                context.showToast("名单更新失败：${error.message ?: "未知错误"}")
            }
            .getOrNull()
            ?.let { configuration = it }
        isConfigurationLoading = false
    }

    SettingsScaffold(
        title = localizedText(title),
        onBack = onBack,
        actions = {
            IconButton(
                enabled = !avatarLoader.isRefreshing,
                onClick = {
                    scope.launch {
                        val refreshedConfiguration = runCatching {
                            RecognitionMembersRepository.refresh(context.applicationContext)
                        }.getOrElse { error ->
                            context.showToast("名单更新失败：${error.message ?: "未知错误"}")
                            return@launch
                        }
                        if (refreshedConfiguration != null) {
                            configuration = refreshedConfiguration
                            context.showToast("名单已更新，正在加载头像")
                            return@launch
                        }
                        val result = avatarLoader.retryMissingOrFailed()
                        val message = when {
                            result.refreshedCount == 0 && result.failedCount == 0 -> "头像均已缓存，无需刷新"
                            result.failedCount == 0 -> "已刷新 ${result.refreshedCount} 个头像"
                            else -> "已刷新 ${result.refreshedCount} 个头像，${result.failedCount} 个头像仍未加载"
                        }
                        context.showToast(message, Toast.LENGTH_SHORT)
                    }
                }
            ) {
                if (avatarLoader.isRefreshing) {
                    CircularProgressIndicator(modifier = Modifier.padding(10.dp))
                } else {
                    Icon(imageVector = Icons.Default.Refresh, contentDescription = localizedText("刷新头像"))
                }
            }
            IconButton(onClick = {
                newestFirst = !newestFirst
                context.showToast(if (newestFirst) "当前按赞助时间由晚到早排列" else "当前按赞助时间由早到晚排列")
            }) {
                Icon(
                    imageVector = Icons.Default.SwapVert,
                    contentDescription = localizedText(if (newestFirst) "当前按赞助时间由晚到早排列，点击切换为由早到晚" else "当前按赞助时间由早到晚排列，点击切换为由晚到早")
                )
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
        ) {
            SettingsInfoText(
                text = localizedText("感谢每一位支持谛听项目的朋友！名单默认按赞助时间由早到晚排列，可通过右上角按钮切换为由晚到早；与赞助金额无关，每一份支持都同样珍贵。"),
                modifier = Modifier.padding(top = 8.dp)
            )
            if (isConfigurationLoading) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
            } else {
                RecognitionList(
                    members = displayedSponsors,
                    emptyText = localizedText("暂时还没有赞助者，期待在这里写下你的名字。"),
                    avatarStates = avatarLoader.states
                )
            }
        }
    }
}
