package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsItem

@Composable
internal fun SubscriptionGroupActionDialog(
    group: SubscriptionGroupEntity,
    onDismiss: () -> Unit,
    onRename: () -> Unit,
    onDissolve: () -> Unit,
    onDeleteSubscriptions: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(group.name) },
        text = {
            Column {
                SettingsItem(localizedText("重命名分组"), leadingIcon = Icons.Default.Edit, onClick = onRename)
                SettingsDivider()
                SettingsItem(localizedText("解散分组"), leadingIcon = Icons.Default.Delete, onClick = onDissolve)
                SettingsDivider()
                SettingsItem(localizedText("删除本组全部订阅"), leadingIcon = Icons.Default.Delete, titleColor = MaterialTheme.colorScheme.error, onClick = onDeleteSubscriptions)
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(localizedText("取消")) } }
    )
}

@Composable
internal fun RenameGroupDialog(
    group: SubscriptionGroupEntity,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit
) {
    var name by remember(group.id) { mutableStateOf(group.name) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText("重命名分组")) },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                label = { Text(localizedText("分组名称")) },
                singleLine = true,
                shape = SettingsCornerShape,
                modifier = Modifier.fillMaxWidth()
            )
        },
        confirmButton = {
            TextButton(
                onClick = { onConfirm(name.trim()) },
                enabled = name.isNotBlank()
            ) {
                Text(localizedText("保存"))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}
