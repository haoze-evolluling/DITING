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
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import kotlinx.coroutines.launch

private val CO_BUILDERS = listOf(
    RecognitionMember(
        name = "AceTaffy1883",
        avatarFileName = "acetaffy1883_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "alone",
        avatarFileName = "alone_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "恐龙复生",
        avatarFileName = "konglongfusheng_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "乐野",
        avatarFileName = "leye_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "理塘丁真",
        avatarFileName = "litangdingzhen_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "睿上源",
        avatarFileName = "ruishangyuan_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "天涯浮客",
        avatarFileName = "tianyafuke_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "妄炁",
        avatarFileName = "wangqi_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "widiOA",
        avatarFileName = "widioa_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "心疼头头哥",
        avatarFileName = "xintengtoutouge_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    ),
    RecognitionMember(
        name = "遇屿",
        avatarFileName = "yuyu_avatar.jpg",
        acknowledgement = "感谢为谛听提出建议与帮助测试"
    )
)

@Composable
fun CoBuilderListScreen(
    onBack: () -> Unit,
    title: String = "共建者名单"
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val avatarLoader = rememberRecognitionAvatarLoader(CO_BUILDERS)
    SettingsScaffold(
        title = title,
        onBack = onBack,
        actions = {
            IconButton(
                enabled = !avatarLoader.isRefreshing,
                onClick = {
                    scope.launch {
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
                members = CO_BUILDERS,
                emptyText = "暂时还没有共建者，期待在这里写下你的名字。",
                avatarStates = avatarLoader.states
            )
        }
    }
}
