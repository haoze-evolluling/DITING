package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold

@Composable
fun SettingsScreen(onBack: () -> Unit, onNavigateToRoute: (String) -> Unit) {
    SettingsScaffold(
        title = stringResource(R.string.other_settings),
        onBack = onBack
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsSection.entries.sortedBy { it.order }.forEach { section ->
                val entries = ScreenDestinations.mainEntries.filter { it.mainSection == section }
                if (entries.isNotEmpty()) {
                    item {
                        SettingsGroupTitle(
                            if (section == SettingsSection.OTHER) stringResource(R.string.other_settings) else section.title
                        )
                    }
                    item {
                        SettingsNavigationGroup(
                            items = entries.map { destination ->
                                SettingsNavigationItemData(
                                    title = if (destination.route == Routes.LANGUAGE_SETTINGS) stringResource(R.string.language_settings) else localizedText(destination.title),
                                    subtitle = if (destination.route == Routes.LANGUAGE_SETTINGS) stringResource(R.string.language_settings_summary) else localizedText(destination.description),
                                    leadingIcon = destination.icon,
                                    onClick = { onNavigateToRoute(destination.route) }
                                )
                            }
                        )
                    }
                }
            }
        }
    }
}
