package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
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
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsLoadingContent
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.vpn.DnsProtocol
import com.haoze.dnssr.vpn.DnsProvider

@Composable
fun ProviderManagementScreen(
    onBack: () -> Unit,
    title: String = "服务商管理",
    viewModel: ProviderManagementViewModel = viewModel()
) {
    val context = LocalContext.current
    val providers by viewModel.providers.collectAsStateWithLifecycle()
    val selectedId by viewModel.selectedId.collectAsStateWithLifecycle()
    val message by viewModel.message.collectAsStateWithLifecycle()
    val initialLoading by viewModel.initialLoading.collectAsStateWithLifecycle()

    var showEditDialog by remember { mutableStateOf<DnsProvider?>(null) }
    var showAddDialog by remember { mutableStateOf(false) }
    var providerToDelete by remember { mutableStateOf<DnsProvider?>(null) }
    var selectedProtocol by remember { mutableStateOf(DnsProtocol.DNS) }

    fun handleProviderSelection(provider: DnsProvider) {
        if (provider.id == selectedId) return
        viewModel.select(provider.id)
    }

    NavigationSettledEffect {
        viewModel.activate()
    }

    message?.let { msg ->
        viewModel.clearMessage()
    }

    val selectedProvider = providers.find { it.id == selectedId }

    SettingsScaffold(
        title = title,
        onBack = onBack,
        actions = {
            TextButton(onClick = { showAddDialog = true }, shape = SettingsCornerShape) {
                Text(localizedText("新增"))
            }
        }
    ) { innerPadding ->
        if (initialLoading) {
            SettingsLoadingContent(modifier = Modifier.padding(innerPadding))
        } else {
            Column(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(innerPadding)
            ) {
                selectedProvider?.let {
                    SettingsInfoText(
                        text = localizedText("当前用于解析 DNS：(${it.protocol.label}) ${it.name}"),
                        modifier = Modifier.padding(top = 8.dp)
                    )
                }

                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    item {
                        ProtocolToggleRow(
                            selectedProtocol = selectedProtocol,
                            onSelect = { selectedProtocol = it },
                            modifier = Modifier.padding(start = 16.dp, top = 16.dp, end = 16.dp)
                        )
                    }
                    item {
            SettingsGroupTitle(localizedText("内置 DNS 服务商"))
                    }
                    item {
                        val presetProviders = providers.filter {
                            it.isPreset && it.protocol == selectedProtocol
                        }
                        SettingsSurfaceGroup(
                            content = presetProviders.map { provider ->
                                {
                                    ProviderListItem(
                                        provider = provider,
                                        selected = provider.id == selectedId,
                                        onSelect = { handleProviderSelection(provider) }
                                    )
                                }
                            }
                        )
                    }

                    item {
            SettingsGroupTitle(localizedText("自定义 DNS 服务商"))
                    }
                    item {
                        val userProviders = providers.filter {
                            it.isUserProvider() && it.protocol == selectedProtocol
                        }
                        if (userProviders.isEmpty()) {
                SettingsInfoText(localizedText("暂无 ${selectedProtocol.label} 自定义服务商。点击右上角“新增”添加自己的 DNS 服务。"))
                        } else {
                            SettingsSurfaceGroup(
                                content = userProviders.map { provider ->
                                    {
                                        ProviderListItem(
                                            provider = provider,
                                            selected = provider.id == selectedId,
                                            onSelect = { handleProviderSelection(provider) },
                                            onEdit = { showEditDialog = provider },
                                            onDelete = { providerToDelete = provider }
                                        )
                                    }
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    if (showAddDialog) {
        ProviderEditDialog(
            title = localizedText("新增 DNS 服务商"),
            initialName = "",
            initialProtocol = selectedProtocol,
            initialUrl = "",
            initialHost = "",
            initialPort = when (selectedProtocol) {
                DnsProtocol.DOT -> DnsProvider.DEFAULT_DOT_PORT.toString()
                else -> DnsProvider.DEFAULT_DNS_PORT.toString()
            },
            onDismiss = { showAddDialog = false },
            onConfirm = { name, protocol, url, host, port ->
                viewModel.addProvider(name, protocol, url, host, port)
                selectedProtocol = protocol
                showAddDialog = false
            }
        )
    }

    showEditDialog?.let { provider ->
        ProviderEditDialog(
            title = localizedText("编辑 DNS 服务商"),
            initialName = provider.name,
            initialProtocol = provider.protocol,
            initialUrl = provider.url,
            initialHost = provider.host,
            initialPort = provider.port.toString(),
            onDismiss = { showEditDialog = null },
            onConfirm = { name, protocol, url, host, port ->
                viewModel.updateProvider(provider, name, protocol, url, host, port)
                showEditDialog = null
            }
        )
    }

    providerToDelete?.let { provider ->
        AlertDialog(
            onDismissRequest = { providerToDelete = null },
            title = { Text(localizedText("删除 DNS 服务商")) },
            text = { Text(localizedText("确定删除“${provider.name}”吗？删除后无法再作为解析服务使用。")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteProvider(provider.id)
                        providerToDelete = null
                    }
                ) {
                    Text(localizedText("删除"))
                }
            },
            dismissButton = {
                TextButton(onClick = { providerToDelete = null }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

}

@Composable
private fun ProtocolToggleRow(
    selectedProtocol: DnsProtocol,
    onSelect: (DnsProtocol) -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth()
    ) {
        DnsProtocol.MANAGED_PROTOCOLS.forEach { option ->
            FilterChip(
                selected = selectedProtocol == option,
                onClick = { onSelect(option) },
                label = {
                    Text(
                        text = option.label,
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
private fun ProviderListItem(
    provider: DnsProvider,
    selected: Boolean,
    onSelect: () -> Unit,
    onEdit: (() -> Unit)? = null,
    onDelete: (() -> Unit)? = null
) {
    SettingsItem(
        title = provider.name,
        subtitle = provider.endpointLabel(),
        onClick = onSelect
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
                    IconButton(
                        onClick = onEditClick,
                        modifier = Modifier.size(40.dp)
                    ) {
                        Icon(
                            imageVector = Icons.Default.Edit,
                contentDescription = localizedText("编辑")
                        )
                    }
                }
                onDelete?.let { onDeleteClick ->
                    IconButton(
                        onClick = onDeleteClick,
                        modifier = Modifier.size(40.dp)
                    ) {
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
private fun ProviderEditDialog(
    title: String,
    initialName: String,
    initialProtocol: DnsProtocol,
    initialUrl: String,
    initialHost: String,
    initialPort: String,
    onDismiss: () -> Unit,
    onConfirm: (name: String, protocol: DnsProtocol, url: String, host: String, port: String) -> Unit
) {
    var name by remember { mutableStateOf(initialName) }
    var protocol by remember { mutableStateOf(initialProtocol) }
    var url by remember { mutableStateOf(initialUrl) }
    var host by remember { mutableStateOf(initialHost) }
    var port by remember { mutableStateOf(initialPort) }
    var showAddressError by remember { mutableStateOf(false) }
    val canSave = isProviderInputValid(name, protocol, url, host, port)
    val addressInvalid = !isProviderAddressValid(protocol, url, host)
    val showCurrentAddressError = showAddressError && addressInvalid

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text(localizedText("服务商名称")) },
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
                ProtocolToggleRow(
                    selectedProtocol = protocol,
                    onSelect = {
                        protocol = it
                        if (it == DnsProtocol.DNS) {
                            port = DnsProvider.DEFAULT_DNS_PORT.toString()
                        } else if (it == DnsProtocol.DOT) {
                            port = DnsProvider.DEFAULT_DOT_PORT.toString()
                        }
                        showAddressError = false
                    }
                )
                if (protocol == DnsProtocol.DOH) {
                    OutlinedTextField(
                        value = url,
                        onValueChange = {
                            url = it
                            showAddressError = false
                        },
                        label = { Text(localizedText("${protocol.label} 解析地址")) },
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
                        label = { Text(localizedText("${protocol.label} 服务器地址")) },
                        placeholder = {
                            Text(localizedText(if (protocol == DnsProtocol.DNS) "1.1.1.1 或 example.com" else "example.com"))
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
                        label = { Text(localizedText("${protocol.label} 端口")) },
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
                        shape = SettingsCornerShape,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (canSave) {
                        onConfirm(name, protocol, url, host, port)
                    } else if (addressInvalid) {
                        showAddressError = true
                    }
                }
            ) {
                Text(
                    text = localizedText("保存"),
                    color = if (canSave) {
                        MaterialTheme.colorScheme.primary
                    } else {
                        MaterialTheme.colorScheme.onSurface.copy(alpha = 0.38f)
                    }
                )
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(localizedText("取消"))
            }
        }
    )
}

@Composable
private fun AddressErrorText() {
    Row(
        horizontalArrangement = Arrangement.spacedBy(4.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = Icons.Default.ErrorOutline,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.error,
            modifier = Modifier.size(14.dp)
        )
        Text(
            text = localizedText("当前的地址并不符合要求"),
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodySmall
        )
    }
}

private fun isProviderInputValid(
    name: String,
    protocol: DnsProtocol,
    url: String,
    host: String,
    portText: String
): Boolean {
    if (name.trim().isEmpty()) return false
    return when (protocol) {
        DnsProtocol.DOH -> DnsProvider.isValidDohUrl(url)
        DnsProtocol.DNS -> {
            val port = portText.trim()
                .ifBlank { DnsProvider.DEFAULT_DNS_PORT.toString() }
                .toIntOrNull()
            DnsProvider.isValidDnsHost(host) && port != null && DnsProvider.isValidDotPort(port)
        }
        DnsProtocol.DOT -> {
            val port = portText.trim()
                .ifBlank { DnsProvider.DEFAULT_DOT_PORT.toString() }
                .toIntOrNull()
            DnsProvider.isValidDotHost(host) && port != null && DnsProvider.isValidDotPort(port)
        }
    }
}

private fun isProviderAddressValid(
    protocol: DnsProtocol,
    url: String,
    host: String
): Boolean {
    return when (protocol) {
        DnsProtocol.DOH -> DnsProvider.isValidDohUrl(url)
        DnsProtocol.DNS -> DnsProvider.isValidDnsHost(host)
        DnsProtocol.DOT -> DnsProvider.isValidDotHost(host)
    }
}
