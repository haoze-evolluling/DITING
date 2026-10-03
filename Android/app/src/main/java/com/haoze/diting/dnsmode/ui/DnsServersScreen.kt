package com.haoze.diting.dnsmode.ui

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.haoze.diting.dnsmode.model.DnsModeProtocol
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import com.haoze.diting.dnsmode.model.DnsUpstreamValidator
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.ProviderEditDialog
import com.haoze.diting.ui.components.ProviderManagementListContent
import com.haoze.diting.ui.localizedText

@Composable
fun DnsServersScreen(
    upstreams: List<DnsUpstreamServer>,
    selectedUpstreamId: String,
    activeUpstream: DnsUpstreamServer?,
    onSelectUpstream: (String) -> Unit,
    onAddUpstream: (name: String, protocol: DnsModeProtocol, address: String, port: Int) -> Unit,
    onUpdateUpstream: (DnsUpstreamServer) -> Unit,
    onDeleteUpstream: (String) -> Unit,
    selectedProtocol: DnsModeProtocol,
    onSelectProtocol: (DnsModeProtocol) -> Unit,
    showAddDialog: Boolean,
    onDismissAddDialog: () -> Unit,
    modifier: Modifier = Modifier,
    contentBottomPadding: Dp = 108.dp
) {
    var editingUpstream by remember { mutableStateOf<DnsUpstreamServer?>(null) }
    var upstreamToDelete by remember { mutableStateOf<DnsUpstreamServer?>(null) }

    val resolvedActive = activeUpstream ?: upstreams.find { it.id == selectedUpstreamId }

    ProviderManagementListContent(
        activeItemText = resolvedActive?.let {
            localizedText("当前用于解析 DNS：(${it.protocol.label})") + " " + localizedText(it.name)
        },
        selectedProtocol = selectedProtocol,
        protocols = DnsModeProtocol.entries,
        protocolLabel = { it.label },
        onSelectProtocol = onSelectProtocol,
        presetItems = upstreams.filter { !it.isCustom && it.protocol == selectedProtocol },
        customItems = upstreams.filter { it.isCustom && it.protocol == selectedProtocol },
        selectedItemId = selectedUpstreamId,
        itemId = { it.id },
        itemTitle = { it.name },
        itemSubtitle = { it.endpointLabel() },
        onSelectItem = { server ->
            if (server.id != selectedUpstreamId) {
                onSelectUpstream(server.id)
            }
        },
        onEditItem = { editingUpstream = it },
        onDeleteItem = { upstreamToDelete = it },
        contentPadding = PaddingValues(bottom = contentBottomPadding),
        modifier = modifier
    )

    if (showAddDialog) {
        ProviderEditDialog(
            title = localizedText("新增 DNS 服务商"),
            initialName = "",
            initialProtocol = selectedProtocol,
            protocols = DnsModeProtocol.entries,
            protocolLabel = { it.label },
            isUrlBasedProtocol = { it == DnsModeProtocol.DOH },
            defaultPortForProtocol = { it.defaultPort },
            initialUrl = "",
            initialHost = "",
            initialPort = selectedProtocol.defaultPort.toString(),
            onDismiss = onDismissAddDialog,
            onConfirm = { name, protocol, url, host, port ->
                val address = if (protocol == DnsModeProtocol.DOH) url else host
                val parsedPort = DnsUpstreamValidator.parsePort(port, protocol)
                onAddUpstream(name, protocol, address, parsedPort)
                onSelectProtocol(protocol)
                onDismissAddDialog()
            },
            validateInput = { name, protocol, url, host, port ->
                val addr = if (protocol == DnsModeProtocol.DOH) url else host
                name.trim().isNotEmpty() &&
                    DnsUpstreamValidator.validateAddress(protocol, addr) == null &&
                    DnsUpstreamValidator.validatePort(port, protocol) == null
            },
            validateAddress = { protocol, url, host ->
                val addr = if (protocol == DnsModeProtocol.DOH) url else host
                DnsUpstreamValidator.validateAddress(protocol, addr) == null
            }
        )
    }

    editingUpstream?.let { server ->
        ProviderEditDialog(
            title = localizedText("编辑 DNS 服务商"),
            initialName = server.name,
            initialProtocol = server.protocol,
            protocols = DnsModeProtocol.entries,
            protocolLabel = { it.label },
            isUrlBasedProtocol = { it == DnsModeProtocol.DOH },
            defaultPortForProtocol = { it.defaultPort },
            initialUrl = if (server.protocol == DnsModeProtocol.DOH) server.address else "",
            initialHost = if (server.protocol != DnsModeProtocol.DOH) server.address else "",
            initialPort = server.port.toString(),
            onDismiss = { editingUpstream = null },
            onConfirm = { name, protocol, url, host, port ->
                val address = if (protocol == DnsModeProtocol.DOH) url else host
                val parsedPort = DnsUpstreamValidator.parsePort(port, protocol)
                onUpdateUpstream(
                    server.copy(
                        name = name,
                        protocol = protocol,
                        address = address,
                        port = parsedPort
                    )
                )
                editingUpstream = null
            },
            validateInput = { name, protocol, url, host, port ->
                val addr = if (protocol == DnsModeProtocol.DOH) url else host
                name.trim().isNotEmpty() &&
                    DnsUpstreamValidator.validateAddress(protocol, addr) == null &&
                    DnsUpstreamValidator.validatePort(port, protocol) == null
            },
            validateAddress = { protocol, url, host ->
                val addr = if (protocol == DnsModeProtocol.DOH) url else host
                DnsUpstreamValidator.validateAddress(protocol, addr) == null
            }
        )
    }

    upstreamToDelete?.let { server ->
        AppConfirmDialog(
            onDismissRequest = { upstreamToDelete = null },
            title = "删除 DNS 服务商",
            message = "确定删除“${server.name}”吗？删除后无法再作为解析服务使用。",
            confirmLabel = "删除",
            destructive = true,
            onConfirm = {
                onDeleteUpstream(server.id)
                upstreamToDelete = null
            }
        )
    }
}
