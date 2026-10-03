package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.haoze.diting.R
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsNavigationGroup
import com.haoze.diting.ui.components.SettingsNavigationItemData
import com.haoze.diting.ui.components.SettingsScaffold

@Composable
fun SettingsScreen(
    onBack: () -> Unit = {},
    onNavigateToRoute: (String) -> Unit,
    showBackIcon: Boolean = true,
    contentBottomPadding: androidx.compose.ui.unit.Dp = 0.dp
) {
    SettingsScaffold(
        title = stringResource(R.string.other_settings),
        onBack = onBack,
        showBackIcon = showBackIcon,
        containerColor = if (!showBackIcon) Color.Transparent else MaterialTheme.colorScheme.background,
        topBarContainerColor = if (!showBackIcon) Color.Transparent else MaterialTheme.colorScheme.background
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(top = innerPadding.calculateTopPadding()),
            contentPadding = PaddingValues(
                start = 0.dp,
                top = 0.dp,
                end = 0.dp,
                bottom = innerPadding.calculateBottomPadding() + contentBottomPadding
            ),
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

