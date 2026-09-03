package com.haoze.dnssr.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.window.DialogWindowProvider
import com.haoze.dnssr.ui.components.DnsProtocolBadge
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.vpn.DnsProvider

internal const val MANAGE_PROVIDER_ID = "__manage__"
internal const val PROVIDER_VISIBILITY_ID = "__provider_visibility__"

internal fun raceProviderSummary(providerNames: List<String>): String {
    if (providerNames.isEmpty()) return "未选择服务商"
    val names = providerNames.take(2).joinToString("、")
    val suffix = if (providerNames.size > 2) " 等" else ""
    return "已选 ${providerNames.size} 个：$names$suffix"
}

@Composable
internal fun ProviderSelectionDialog(
    visible: Boolean,
    providers: List<DnsProvider>,
    onDismissRequest: () -> Unit,
    onProviderSelected: (DnsProvider) -> Unit
) {
    val dialogVisibility = remember { MutableTransitionState(false) }
    dialogVisibility.targetState = visible

    if (dialogVisibility.currentState || dialogVisibility.targetState) {
        Dialog(
            onDismissRequest = onDismissRequest,
            properties = DialogProperties(usePlatformDefaultWidth = false)
        ) {
            DisableDialogDimming()
            AnimatedVisibility(
                visibleState = dialogVisibility,
                enter = fadeIn(animationSpec = tween(120)) +
                    scaleIn(initialScale = 0.92f, animationSpec = tween(180)),
                exit = fadeOut(animationSpec = tween(90)) +
                    scaleOut(targetScale = 0.92f, animationSpec = tween(120))
            ) {
                Surface(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 24.dp)
                        .heightIn(max = 520.dp),
                    shape = SettingsCornerShape,
                    color = MaterialTheme.colorScheme.surface,
                    tonalElevation = 6.dp
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .verticalScroll(rememberScrollState())
                            .padding(vertical = 8.dp)
                    ) {
                        Text(
                            text = localizedText("解析服务"),
                            style = MaterialTheme.typography.titleLarge,
                            fontSize = 24.sp,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp)
                        )
                        providers.forEachIndexed { index, provider ->
                            DropdownMenuItem(
                                text = {
                                    ProviderDropdownText(
                                        provider = provider,
                                        showProtocolBadge = provider.id != MANAGE_PROVIDER_ID &&
                                            provider.id != PROVIDER_VISIBILITY_ID
                                    )
                                },
                                onClick = { onProviderSelected(provider) },
                                modifier = Modifier.padding(horizontal = 8.dp)
                            )
                            if (index < providers.lastIndex) {
                                Spacer(modifier = Modifier.padding(vertical = 1.dp))
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun DisableDialogDimming() {
    val view = LocalView.current
    SideEffect {
        (view.parent as? DialogWindowProvider)?.window?.setDimAmount(0f)
    }
}

@Composable
private fun ProviderDropdownText(
    provider: DnsProvider,
    showProtocolBadge: Boolean
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Text(
            text = localizedText(provider.name),
            style = MaterialTheme.typography.bodyLarge
        )
        Spacer(modifier = Modifier.weight(1f))
        if (showProtocolBadge) {
            DnsProtocolBadge(protocol = provider.protocol)
        }
    }
}

@Composable
internal fun ProviderEndpointList(providers: List<DnsProvider>, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp)
    ) {
        providers.forEach { provider ->
            Text(
                text = provider.endpointLabel(),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }
    }
}
