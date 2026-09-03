package com.haoze.dnssr.ui.traffic

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.HelpOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.dnssr.ui.components.AppAlertDialog
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.localizedText

@Composable
fun TrafficAttributionDialog(
    onDismiss: () -> Unit
) {
    val colors = MaterialTheme.colorScheme

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Icon(
                    imageVector = Icons.AutoMirrored.Filled.HelpOutline,
                    contentDescription = null,
                    tint = colors.primary,
                    modifier = Modifier.size(24.dp)
                )
                Text(
                    text = localizedText("为什么系统流量全算给谛听？"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
            }
        },
        text = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(14.dp)
            ) {
                Surface(
                    color = colors.primaryContainer.copy(alpha = 0.4f),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Column(
                        modifier = Modifier.padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Text(
                            text = localizedText("💡 真实流量关系等式"),
                            style = MaterialTheme.typography.labelMedium,
                            fontWeight = FontWeight.Bold,
                            color = colors.primary
                        )
                        Text(
                            text = localizedText("系统统计 谛听 (50 GB) = 哔哩哔哩 (30 GB) + 抖音 (15 GB) + 微信 (5 GB)"),
                            style = MaterialTheme.typography.bodySmall,
                            fontWeight = FontWeight.SemiBold,
                            color = colors.onPrimaryContainer
                        )
                    }
                }

                Text(
                    text = localizedText("1. Linux 内核归属机制"),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = colors.onSurface
                )
                Text(
                    text = localizedText("Android 底层网络栈严格按照「创建物理连接的进程 UID」统计流量。当开启 VPN 代理时，各应用的原始网络数据被路由给谛听，谛听通过自身的受保护套接字与外部网络传输。因此在系统设置眼里，所有外网流量都是由谛听创建的 Socket 产生的。"),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant,
                    lineHeight = 20.sp
                )

                Text(
                    text = localizedText("2. 为什么第三方软件无法修改系统设置"),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = colors.onSurface
                )
                Text(
                    text = localizedText("修改系统全局流量账本需要系统级签名权限（android.permission.UPDATE_DEVICE_STATS）。任何遵循 Google 安全规范的标准 VPN 应用都无权擅自篡改系统设置里的流量报表。"),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant,
                    lineHeight = 20.sp
                )

                Text(
                    text = localizedText("3. 谛听的透明性与隐私承诺"),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Bold,
                    color = colors.onSurface
                )
                Text(
                    text = localizedText("谛听本身绝不主动消耗外网业务流量。本页面展示的各应用实时网速和历史消耗，即为您设备上各个真实应用通过谛听中转时的精确流量分解，让您清清楚楚掌控每一字节流向。"),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant,
                    lineHeight = 20.sp
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(text = localizedText("我知道了"))
            }
        }
    )
}
