package com.haoze.dnssr.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.theme.ThemeColorStyle
import com.haoze.dnssr.vpn.DnsVpnService

@Composable
fun ThemeColorSettingsScreen(
    onBack: () -> Unit,
    title: String,
    onThemeColorStyleChanged: (ThemeColorStyle) -> Unit
) {
    val context = LocalContext.current
    var selectedStyle by remember { mutableStateOf(AppSettings.getThemeColorStyle(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            item { SettingsGroupTitle(localizedText("主题色")) }
            item {
                SettingsSurfaceGroup(
                    content = ThemeColorStyle.entries.map { style ->
                        {
                            SettingsItem(
                                title = localizedText(style.displayName),
                                subtitle = if (style == ThemeColorStyle.SYSTEM) localizedText("使用系统壁纸的动态取色") else null,
                                onClick = {
                                    selectedStyle = style
                                    AppSettings.setThemeColorStyle(context, style)
                                    DnsVpnService.refreshFloatingLogOverlay(context)
                                    onThemeColorStyleChanged(style)
                                }
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(28.dp)
                                        .background(style.lightPrimary, CircleShape),
                                    contentAlignment = Alignment.Center
                                ) {
                                    if (selectedStyle == style) {
                                        Icon(
                                            imageVector = Icons.Filled.CheckCircle,
                                            contentDescription = localizedText("已选中"),
                                            tint = Color.White,
                                            modifier = Modifier.size(18.dp)
                                        )
                                    }
                                }
                            }
                        }
                    }
                )
            }
        }
    }
}
