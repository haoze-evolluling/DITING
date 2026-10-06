package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.AppDialogButton
import com.haoze.diting.ui.components.SettingsOutlinedActionButton

@Composable
fun DomainActionDialog(
    domain: String,
    dismiss: () -> Unit,
    copy: () -> Unit,
    add: (Boolean) -> Unit,
    analyze: (() -> Unit)? = null
) {
    AppAlertDialog(
        onDismissRequest = dismiss,
        title = { Text(localizedText("处理域名")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(domain, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.primary)
                if (analyze != null) {
                    SettingsOutlinedActionButton(analyze, Modifier.fillMaxWidth()) {
                        Icon(
                            Icons.Filled.AutoAwesome,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = MaterialTheme.colorScheme.primary
                        )
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(
                            localizedText("AI 分析该域名"),
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = FontWeight.SemiBold
                        )
                    }
                }
                SettingsOutlinedActionButton(copy, Modifier.fillMaxWidth()) { Text(localizedText("复制域名")) }
                SettingsOutlinedActionButton({ add(true) }, Modifier.fillMaxWidth()) { Text(localizedText("加入白名单规则")) }
                SettingsOutlinedActionButton({ add(false) }, Modifier.fillMaxWidth()) { Text(localizedText("加入屏蔽规则")) }
            }
        },
        confirmButton = { AppDialogButton(label = "取消", onClick = dismiss) }
    )
}
