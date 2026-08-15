package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Column
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
import androidx.compose.runtime.Composable
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

private val SPONSORS = listOf(
    RecognitionMember(
        name = "alone",
        avatarFileName = "alone_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "睿上源",
        avatarFileName = "ruishangyuan_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "理塘丁真",
        avatarFileName = "litangdingzhen_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "天涯浮客",
        avatarFileName = "tianyafuke_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "AceTaffy1883",
        avatarFileName = "acetaffy1883_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "心疼头头哥",
        avatarFileName = "xintengtoutouge_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "恐龙复生",
        avatarFileName = "konglongfusheng_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "xo人头马",
        avatarFileName = "xorentouma_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "过江龙傲天",
        avatarFileName = "guojianglongaotian_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "狸",
        avatarFileName = "li_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    ),
    RecognitionMember(
        name = "lucasyr",
        avatarFileName = "lucasyr_avatar.jpg",
        acknowledgement = "感谢您对谛听项目的赞助支持"
    )
)

@Composable
fun SponsorListScreen(
    onBack: () -> Unit,
    title: String = "赞助者名单"
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val avatarLoader = rememberRecognitionAvatarLoader(SPONSORS)
    var newestFirst by remember { mutableStateOf(false) }
    val displayedSponsors = if (newestFirst) SPONSORS.asReversed() else SPONSORS

    SettingsScaffold(
        title = localizedText(title),
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
            IconButton(onClick = {
                newestFirst = !newestFirst
                Toast.makeText(
                    context,
                    localizedText(context, if (newestFirst) "当前按赞助时间由晚到早排列" else "当前按赞助时间由早到晚排列"),
                    Toast.LENGTH_SHORT
                ).show()
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
            RecognitionList(
                members = displayedSponsors,
                emptyText = localizedText("暂时还没有赞助者，期待在这里写下你的名字。"),
                avatarStates = avatarLoader.states
            )
        }
    }
}
