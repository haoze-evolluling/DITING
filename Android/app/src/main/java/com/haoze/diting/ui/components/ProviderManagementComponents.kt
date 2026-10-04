package com.haoze.diting.ui.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.localizedText

@Composable
fun <T> ProtocolToggleRow(
    protocols: List<T>,
    selectedProtocol: T,
    onSelect: (T) -> Unit,
    protocolLabel: (T) -> String,
    modifier: Modifier = Modifier
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth()
    ) {
        protocols.forEach { option ->
            FilterChip(
                selected = selectedProtocol == option,
                onClick = { onSelect(option) },
                label = {
                    Text(
                        text = protocolLabel(option),
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                },
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
fun ProviderListItem(
    title: String,
    subtitle: String,
    selected: Boolean,
    onSelect: () -> Unit,
    modifier: Modifier = Modifier,
    onEdit: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null
) {
    SettingsItem(
        title = localizedText(title),
        subtitle = subtitle,
        onClick = onSelect,
        modifier = modifier
    ) {
        if (selected) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = localizedText("已选中"),
                tint = MaterialTheme.colorScheme.primary
            )
        }
        if (onEdit != null || onDelete != null) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                onEdit?.let { onEditClick ->
                    IconButton(onClick = onEditClick) {
                        Icon(
                            imageVector = Icons.Default.Edit,
                            contentDescription = localizedText("编辑")
                        )
                    }
                }
                onDelete?.let { onDeleteClick ->
                    IconButton(onClick = onDeleteClick) {
                        Icon(
                            imageVector = Icons.Default.Delete,
                            contentDescription = localizedText("删除")
                        )
                    }
                }
            }
        }
    }
}

@Composable
fun AddressErrorText(
    message: String = localizedText("当前的地址并不符合要求"),
    modifier: Modifier = Modifier
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
    ) {
        Icon(
            imageVector = Icons.Default.ErrorOutline,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.error,
            modifier = Modifier.size(14.dp)
        )
        Text(
            text = message,
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall
        )
    }
}

@Composable
fun <P> ProviderEditDialog(
    title: String,
    initialName: String,
    initialProtocol: P,
    protocols: List<P>,
    protocolLabel: (P) -> String,
    isUrlBasedProtocol: (P) -> Boolean,
    defaultPortForProtocol: (P) -> Int,
    initialUrl: String,
    initialHost: String,
    initialPort: String,
    onDismiss: () -> Unit,
    onConfirm: (name: String, protocol: P, url: String, host: String, port: String) -> Unit,
    validateInput: (name: String, protocol: P, url: String, host: String, port: String) -> Boolean,
    validateAddress: (protocol: P, url: String, host: String) -> Boolean,
    nameLabel: String = localizedText("服务商名称")
) {
    var name by remember { mutableStateOf(initialName) }
    var protocol by remember { mutableStateOf(initialProtocol) }
    var url by remember { mutableStateOf(initialUrl) }
    var host by remember { mutableStateOf(initialHost) }
    var port by remember { mutableStateOf(initialPort) }
    var showAddressError by remember { mutableStateOf(false) }
    val canSave = validateInput(name, protocol, url, host, port)
    val addressInvalid = !validateAddress(protocol, url, host)
    val showCurrentAddressError = showAddressError && addressInvalid

    AppAlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(nameLabel) },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
                ProtocolToggleRow(
                    protocols = protocols,
                    selectedProtocol = protocol,
                    onSelect = { newProtocol ->
                        protocol = newProtocol
                        if (!isUrlBasedProtocol(newProtocol)) {
                            port = defaultPortForProtocol(newProtocol).toString()
                        }
                        showAddressError = false
                    },
                    protocolLabel = protocolLabel
                )
                if (isUrlBasedProtocol(protocol)) {
                    OutlinedTextField(
                        value = url,
                        onValueChange = {
                            url = it
                            showAddressError = false
                        },
                        label = { Text(localizedText("${protocolLabel(protocol)} 解析地址")) },
                        placeholder = { Text(localizedText("https://example.com")) },
                        isError = showCurrentAddressError,
                        supportingText = {
                            if (showCurrentAddressError) {
                                AddressErrorText()
                            }
                        },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    OutlinedTextField(
                        value = host,
                        onValueChange = {
                            host = it
                            showAddressError = false
                        },
                        label = { Text(localizedText("${protocolLabel(protocol)} 服务器地址")) },
                        placeholder = {
                            Text(localizedText("1.1.1.1 或 example.com"))
                        },
                        isError = showCurrentAddressError,
                        supportingText = {
                            if (showCurrentAddressError) {
                                AddressErrorText()
                            }
                        },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = port,
                        onValueChange = { port = it.filter { char -> char.isDigit() } },
                        label = { Text(localizedText("${protocolLabel(protocol)} 端口")) },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        },
        confirmButton = {
            AppDialogButton(
                label = "保存",
                enabled = canSave || addressInvalid,
                onClick = {
                    if (canSave) {
                        onConfirm(name, protocol, url, host, port)
                    } else if (addressInvalid) {
                        showAddressError = true
                    }
                }
            )
        },
        dismissButton = {
            AppDialogButton(label = "取消", onClick = onDismiss)
        }
    )
}

@Composable
fun <T, P> ProviderManagementListContent(
    activeItemText: String?,
    selectedProtocol: P,
    protocols: List<P>,
    protocolLabel: (P) -> String,
    onSelectProtocol: (P) -> Unit,
    presetItems: List<T>,
    customItems: List<T>,
    selectedItemId: String?,
    itemId: (T) -> String,
    itemTitle: (T) -> String,
    itemSubtitle: (T) -> String,
    onSelectItem: (T) -> Unit,
    onEditItem: (T) -> Unit,
    onDeleteItem: (T) -> Unit,
    modifier: Modifier = Modifier,
    contentPadding: PaddingValues = PaddingValues(0.dp),
    presetGroupTitle: String = localizedText("内置 DNS 服务商"),
    customGroupTitle: String = localizedText("自定义 DNS 服务商"),
    customEmptyText: String = localizedText("暂无 ${protocolLabel(selectedProtocol)} 自定义服务商。点击右上角“新增”添加自己的 DNS 服务。")
) {
    Column(
        modifier = modifier.fillMaxSize()
    ) {
        activeItemText?.let {
            SettingsInfoText(
                text = it,
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = contentPadding,
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                ProtocolToggleRow(
                    protocols = protocols,
                    selectedProtocol = selectedProtocol,
                    onSelect = onSelectProtocol,
                    protocolLabel = protocolLabel,
                    modifier = Modifier.padding(start = SettingsCardMargin, top = 16.dp, end = 16.dp)
                )
            }
            item {
                SettingsGroupTitle(presetGroupTitle)
            }
            item {
                if (presetItems.isEmpty()) {
                    SettingsInfoText(localizedText("暂无内置服务商"))
                } else {
                    SettingsSurfaceGroup(
                        content = presetItems.map { item ->
                            {
                                ProviderListItem(
                                    title = itemTitle(item),
                                    subtitle = itemSubtitle(item),
                                    selected = itemId(item) == selectedItemId,
                                    onSelect = { onSelectItem(item) }
                                )
                            }
                        }
                    )
                }
            }

            item {
                SettingsGroupTitle(customGroupTitle)
            }
            item {
                if (customItems.isEmpty()) {
                    SettingsInfoText(customEmptyText)
                } else {
                    SettingsSurfaceGroup(
                        content = customItems.map { item ->
                            {
                                ProviderListItem(
                                    title = itemTitle(item),
                                    subtitle = itemSubtitle(item),
                                    selected = itemId(item) == selectedItemId,
                                    onSelect = { onSelectItem(item) },
                                    onEdit = { onEditItem(item) },
                                    onDelete = { onDeleteItem(item) }
                                )
                            }
                        }
                    )
                }
            }
        }
    }
}
