package com.haoze.diting.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.ProviderEditDialog
import com.haoze.diting.ui.components.ProviderManagementListContent
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsLoadingContent
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.vpn.DnsProtocol
import com.haoze.diting.vpn.DnsProvider

@Composable
fun ProviderManagementScreen(
    onBack: () -> Unit,
    title: String = "服务商管理",
    dataset: com.haoze.diting.data.RuleDataset = com.haoze.diting.data.RuleDataset.NORMAL,
    viewModel: ProviderManagementViewModel = viewModel(
        factory = ProviderManagementViewModel.Factory(
            androidx.compose.ui.platform.LocalContext.current.applicationContext as android.app.Application,
            dataset
        )
    )
) {
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

    message?.let {
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
            ProviderManagementListContent(
                activeItemText = selectedProvider?.let {
                    localizedText("当前用于解析 DNS：(${it.protocol.label})") + " " + localizedText(it.name)
                },
                selectedProtocol = selectedProtocol,
                protocols = DnsProtocol.MANAGED_PROTOCOLS,
                protocolLabel = { it.label },
                onSelectProtocol = { selectedProtocol = it },
                presetItems = providers.filter {
                    it.isPreset && it.protocol == selectedProtocol
                },
                customItems = providers.filter {
                    it.isUserProvider() && it.protocol == selectedProtocol
                },
                selectedItemId = selectedId,
                itemId = { it.id },
                itemTitle = { it.name },
                itemSubtitle = { it.endpointLabel() },
                onSelectItem = ::handleProviderSelection,
                onEditItem = { showEditDialog = it },
                onDeleteItem = { providerToDelete = it },
                modifier = Modifier.padding(innerPadding)
            )
        }
    }

    if (showAddDialog) {
        ProviderEditDialog(
            title = localizedText("新增 DNS 服务商"),
            initialName = "",
            initialProtocol = selectedProtocol,
            protocols = DnsProtocol.MANAGED_PROTOCOLS,
            protocolLabel = { it.label },
            isUrlBasedProtocol = { it == DnsProtocol.DOH },
            defaultPortForProtocol = {
                if (it == DnsProtocol.DOT) DnsProvider.DEFAULT_DOT_PORT else DnsProvider.DEFAULT_DNS_PORT
            },
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
            },
            validateInput = { name, protocol, url, host, port ->
                isProviderInputValid(name, protocol, url, host, port)
            },
            validateAddress = { protocol, url, host ->
                isProviderAddressValid(protocol, url, host)
            }
        )
    }

    showEditDialog?.let { provider ->
        ProviderEditDialog(
            title = localizedText("编辑 DNS 服务商"),
            initialName = provider.name,
            initialProtocol = provider.protocol,
            protocols = DnsProtocol.MANAGED_PROTOCOLS,
            protocolLabel = { it.label },
            isUrlBasedProtocol = { it == DnsProtocol.DOH },
            defaultPortForProtocol = {
                if (it == DnsProtocol.DOT) DnsProvider.DEFAULT_DOT_PORT else DnsProvider.DEFAULT_DNS_PORT
            },
            initialUrl = provider.url,
            initialHost = provider.host,
            initialPort = provider.port.toString(),
            onDismiss = { showEditDialog = null },
            onConfirm = { name, protocol, url, host, port ->
                viewModel.updateProvider(provider, name, protocol, url, host, port)
                showEditDialog = null
            },
            validateInput = { name, protocol, url, host, port ->
                isProviderInputValid(name, protocol, url, host, port)
            },
            validateAddress = { protocol, url, host ->
                isProviderAddressValid(protocol, url, host)
            }
        )
    }

    providerToDelete?.let { provider ->
        AppConfirmDialog(
            onDismissRequest = { providerToDelete = null },
            title = "删除 DNS 服务商",
            message = "确定删除“${provider.name}”吗？删除后无法再作为解析服务使用。",
            confirmLabel = "删除",
            destructive = true,
            onConfirm = {
                viewModel.deleteProvider(provider.id)
                providerToDelete = null
            }
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
