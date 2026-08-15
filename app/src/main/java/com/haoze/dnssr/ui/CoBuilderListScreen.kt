package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
fun CoBuilderListScreen(
    onBack: () -> Unit,
    title: String = "共建者名单"
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var configuration by remember { mutableStateOf<RecognitionMembersConfiguration?>(null) }
    val coBuilders = configuration?.coBuilders.orEmpty()
    val avatarLoader = rememberRecognitionAvatarLoader(coBuilders)
    LaunchedEffect(context.applicationContext) {
        configuration = RecognitionMembersRepository.loadCached(context.applicationContext)
        runCatching { RecognitionMembersRepository.refresh(context.applicationContext) }
            .getOrNull()
            ?.let { configuration = it }
    }
    SettingsScaffold(
        title = title,
        onBack = onBack,
        actions = {
            IconButton(
                enabled = !avatarLoader.isRefreshing,
                onClick = {
                    scope.launch {
                        runCatching { RecognitionMembersRepository.refresh(context.applicationContext) }
                            .getOrNull()?.let { configuration = it }
                        val result = avatarLoader.retryMissingOrFailed()
                        val message = when {
                            result.refreshedCount == 0 && result.failedCount == 0 -> "头像均已缓存，无需刷新"
                            result.failedCount == 0 -> "已刷新 ${result.refreshedCount} 个头像"
                            else -> "已刷新 ${result.refreshedCount} 个头像，${result.failedCount} 个头像仍未加载"
                        }
                        Toast.makeText(context, localizedText(context, message), Toast.LENGTH_SHORT).show()
                    }
                }
            ) {
                if (avatarLoader.isRefreshing) {
                    CircularProgressIndicator(modifier = Modifier.padding(10.dp))
                } else {
                    Icon(imageVector = Icons.Default.Refresh, contentDescription = localizedText("刷新头像"))
                }
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
                text = localizedText("感谢每一位为谛听提出建议、帮助测试的共建者！名单按用户名称的字母顺序排列，中文名称按拼音排序。"),
                modifier = Modifier.padding(top = 8.dp)
            )
            RecognitionList(
                members = coBuilders,
                emptyText = "暂时还没有共建者，期待在这里写下你的名字。",
                avatarStates = avatarLoader.states
            )
        }
    }
}
