package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.DnsVpnService

@Composable
fun DayNightModeScreen(
    onBack: () -> Unit,
    title: String,
    onThemeModeChanged: (AppThemeMode) -> Unit
) {
    val context = LocalContext.current
    var selectedMode by remember { mutableStateOf(AppSettings.getAppThemeMode(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("主题")) }
            item {
                SettingsSurfaceGroup(
                    content = AppThemeMode.entries.map { mode ->
                        {
                            SettingsRadioItem(
                                title = localizedText(mode.displayName),
                                selected = selectedMode == mode,
                                onClick = {
                                    selectedMode = mode
                                    AppSettings.setAppThemeMode(context, mode)
                                    DnsVpnService.refreshFloatingLogOverlay(context)
                                    onThemeModeChanged(mode)
                                }
                            )
                        }
                    }
                )
            }
        }
    }
}
