package com.haoze.dnssr.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem
import com.haoze.dnssr.vpn.cache.DnsCachePreset

@Composable
fun CacheSettingsScreen(
    onBack: () -> Unit,
    title: String = "缓存设置",
    onRuntimeDnsSettingsChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    val scrollState = rememberScrollState()
    var enabled by remember { mutableStateOf(AppSettings.isCacheEnabled(context)) }
    var preset by remember { mutableStateOf(AppSettings.getDnsCachePreset(context)) }

    fun saveEnabled(next: Boolean) {
        enabled = next
        AppSettings.setDnsCachePolicy(context, preset.toPolicy(enabled = next))
        onRuntimeDnsSettingsChanged()
    }

    fun savePreset(next: DnsCachePreset) {
        preset = next
        AppSettings.setDnsCachePolicy(context, next.toPolicy(enabled = enabled))
        onRuntimeDnsSettingsChanged()
    }

    SettingsScaffold(
        title = title,
        onBack = onBack
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsGroupTitle(localizedText("缓存"))
            SettingsSurfaceGroup(content = listOf {
                SettingsSwitchItem(
                    title = localizedText("本地 DNS 缓存"),
                    subtitle = if (enabled) {
                        stringResource(preset.displayName) + "：" + stringResource(preset.summary)
                    } else {
                        localizedText("关闭后每次解析都会请求上游 DNS")
                    },
                    checked = enabled,
                    onCheckedChange = ::saveEnabled
                )
            })
            AnimatedVisibility(
                visible = enabled,
                enter = expandVertically(),
                exit = shrinkVertically()
            ) {
                SettingsSurfaceGroup(
                    content = DnsCachePreset.entries.map { option ->
                        {
                            SettingsRadioItem(
                                title = stringResource(option.displayName),
                                subtitle = stringResource(option.summary) + "。" + stringResource(option.description),
                                selected = preset == option,
                                onClick = { savePreset(option) }
                            )
                        }
                    }
                )
            }
            SettingsInfoText(localizedText("建议使用“标准”。档位会自动设置最长 TTL、最短 TTL 和解析失败兜底时间，不再需要手动填写秒数。"))
        }
    }
}
