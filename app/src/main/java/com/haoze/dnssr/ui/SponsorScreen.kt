package com.haoze.dnssr.ui

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup

private const val SPONSOR_README_URL = "https://github.com/haoze-evolluling/DITING#sponsorship"

@Composable
fun SponsorScreen(
    onBack: () -> Unit,
    title: String = "赞助"
) {
    val context = LocalContext.current
    val openReadme: () -> Unit = {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(SPONSOR_README_URL)))
        }.onFailure {
            context.showToast("无法打开链接", Toast.LENGTH_SHORT)
        }
        Unit
    }

    SettingsScaffold(
        title = localizedText(title),
        onBack = onBack
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
        ) {
            Column(
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                Text(
                    text = localizedText("请作者喝杯蜜雪 🧋"),
                    style = MaterialTheme.typography.headlineSmall,
                    color = MaterialTheme.colorScheme.onSurface,
                    fontWeight = FontWeight.SemiBold
                )
                Text(
                    text = localizedText("如果这个项目帮助到了你，欢迎请作者喝杯蜜雪。"),
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
            SettingsSurfaceGroup(
                content = listOf {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(onClick = openReadme)
                            .padding(horizontal = 16.dp, vertical = 14.dp),
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = localizedText("在 GitHub 查看 README 中的赞助方式"),
                                style = MaterialTheme.typography.titleSmall,
                                color = MaterialTheme.colorScheme.onSurface,
                                fontWeight = FontWeight.Bold
                            )
                            Text(
                                text = SPONSOR_README_URL.removePrefix("https://"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.OpenInNew,
                            contentDescription = localizedText("打开 GitHub README"),
                            tint = MaterialTheme.colorScheme.primary
                        )
                    }
                }
            )

            SettingsGroupTitle(localizedText("你的每一笔支持都会用于"))
            SettingsSurfaceGroup(
                content = listOf {
                    SponsorList(
                        items = listOf(
                            localizedText("持续开发新功能"),
                            localizedText("修复 Bug"),
                            localizedText("购买词元")
                        )
                    )
                }
            )

            SettingsGroupTitle(localizedText("即使不捐赠，也欢迎"))
            SettingsSurfaceGroup(
                content = listOf {
                    SponsorList(
                        items = listOf(
                            localizedText("点一个 Star⭐"),
                            localizedText("提交 Issue"),
                            localizedText("提交 PR"),
                            localizedText("分享给更多人")
                        )
                    )
                }
            )

            Text(
                text = localizedText("感谢每一位支持项目的朋友！"),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.primary,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 24.dp)
            )
        }
    }
}

@Composable
private fun SponsorList(items: List<String>) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        items.forEach { item ->
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Text(
                    text = "•",
                    style = MaterialTheme.typography.bodyLarge,
                    color = MaterialTheme.colorScheme.primary
                )
                Text(
                    text = item,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                    modifier = Modifier.weight(1f)
                )
            }
        }
    }
}
