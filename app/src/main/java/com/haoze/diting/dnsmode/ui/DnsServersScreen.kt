package com.haoze.diting.dnsmode.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.outlined.Dns
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsNavigationItem
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.localizedText

@Composable
fun DnsServersScreen(
    upstreams: List<DnsUpstreamServer>,
    selectedUpstreamId: String,
    onSelectUpstream: (String) -> Unit,
    onAddUpstream: () -> Unit,
    onEditUpstream: (DnsUpstreamServer) -> Unit,
    modifier: Modifier = Modifier,
    contentBottomPadding: Dp = 108.dp
) {
    val selectedUpstream = upstreams.find { it.id == selectedUpstreamId }
    val customServers = upstreams.filter { it.isCustom }
    val presetServers = upstreams.filterNot { it.isCustom }

    Column(
        modifier = modifier.fillMaxSize()
    ) {
        selectedUpstream?.let {
            SettingsInfoText(
                text = localizedText("当前用于解析 DNS：") + localizedText(it.name),
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = contentBottomPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsGroupTitle(localizedText("自定义上游"))
            }

            item {
                SettingsSurfaceGroup(
                    content = buildList {
                        add {
                            SettingsNavigationItem(
                                title = localizedText("添加自定义上游"),
                                subtitle = localizedText("支持 UDP / TCP / DoT / DoH 协议"),
                                leadingIcon = Icons.Default.Add,
                                onClick = onAddUpstream
                            )
                        }
                        customServers.forEach { server ->
                            add {
                                DnsUpstreamListItem(
                                    server = server,
                                    selected = server.id == selectedUpstreamId,
                                    onSelect = {
                                        if (server.id != selectedUpstreamId) {
                                            onSelectUpstream(server.id)
                                        }
                                    },
                                    onEdit = { onEditUpstream(server) }
                                )
                            }
                        }
                    }
                )
            }

            item {
                SettingsGroupTitle(localizedText("预设公共上游 DNS"))
            }

            item {
                SettingsSurfaceGroup(
                    content = presetServers.map { server ->
                        {
                            DnsUpstreamListItem(
                                server = server,
                                selected = server.id == selectedUpstreamId,
                                onSelect = {
                                    if (server.id != selectedUpstreamId) {
                                        onSelectUpstream(server.id)
                                    }
                                },
                                onEdit = null
                            )
                        }
                    }
                )
            }
        }
    }
}

@Composable
private fun DnsUpstreamListItem(
    server: DnsUpstreamServer,
    selected: Boolean,
    onSelect: () -> Unit,
    onEdit: (() -> Unit)?
) {
    SettingsItem(
        title = localizedText(server.name),
        subtitle = if (server.description.isNotBlank()) {
            localizedText(server.description)
        } else {
            server.endpointLabel()
        },
        onClick = onSelect
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            if (onEdit != null) {
                IconButton(onClick = onEdit) {
                    Icon(
                        imageVector = Icons.Default.Edit,
                        contentDescription = localizedText("编辑"),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
            if (selected) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = localizedText("已选中"),
                    tint = MaterialTheme.colorScheme.primary
                )
            }
        }
    }
}
