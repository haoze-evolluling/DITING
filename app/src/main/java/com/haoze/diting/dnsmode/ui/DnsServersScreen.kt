package com.haoze.diting.dnsmode.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.haoze.diting.dnsmode.model.DnsUpstreamServer
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.localizedText

@Composable
fun DnsServersScreen(
    upstreams: List<DnsUpstreamServer>,
    selectedUpstreamId: String,
    onSelectUpstream: (String) -> Unit,
    modifier: Modifier = Modifier,
    contentBottomPadding: Dp = 108.dp
) {
    val selectedUpstream = upstreams.find { it.id == selectedUpstreamId }

    Column(
        modifier = modifier.fillMaxSize()
    ) {
        selectedUpstream?.let {
            SettingsInfoText(
                text = localizedText("当前用于解析 DNS：") + " " + localizedText(it.name),
                modifier = Modifier.padding(top = 8.dp)
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = contentBottomPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsGroupTitle(localizedText("预设公共上游 DNS"))
            }

            item {
                SettingsSurfaceGroup(
                    content = upstreams.map { server ->
                        {
                            DnsUpstreamListItem(
                                server = server,
                                selected = server.id == selectedUpstreamId,
                                onSelect = {
                                    if (server.id != selectedUpstreamId) {
                                        onSelectUpstream(server.id)
                                    }
                                }
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
    onSelect: () -> Unit
) {
    SettingsItem(
        title = localizedText(server.name),
        subtitle = server.endpointLabel(),
        onClick = onSelect
    ) {
        if (selected) {
            Icon(
                imageVector = Icons.Default.CheckCircle,
                contentDescription = localizedText("已选中"),
                tint = MaterialTheme.colorScheme.primary
            )
        }
    }
}

