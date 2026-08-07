package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(onBack: () -> Unit, onNavigateToRoute: (String) -> Unit) {
    var searchQuery by remember { mutableStateOf("") }
    val normalizedQuery = searchQuery.trim()
    val filteredItems = if (normalizedQuery.isEmpty()) emptyList() else
        ScreenDestinations.searchEntries.filter { it.matches(normalizedQuery) }

    Scaffold(
        topBar = {
            TopAppBar(
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    scrolledContainerColor = MaterialTheme.colorScheme.background
                ),
                title = { Text(stringResource(R.string.app_settings)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
            )
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp),
                    shape = RoundedCornerShape(28.dp),
                    singleLine = true,
                    placeholder = { Text(stringResource(R.string.search_settings)) },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = stringResource(R.string.search)) },
                    trailingIcon = if (searchQuery.isNotEmpty()) {{
                        IconButton(onClick = { searchQuery = "" }) {
                            Icon(Icons.Filled.Clear, contentDescription = stringResource(R.string.clear))
                        }
                    }} else null
                )
            }
            if (normalizedQuery.isNotEmpty()) {
                if (filteredItems.isEmpty()) {
                    item { Text(stringResource(R.string.no_matching_settings), modifier = Modifier.padding(32.dp)) }
                } else {
                    items(filteredItems.size) { index ->
                        val setting = filteredItems[index]
                        val subtitleParts = setting.resultSubtitle.split(" · ")
                        val translatedSubtitleBuilder = StringBuilder()
                        for (partIndex in subtitleParts.indices) {
                            if (partIndex > 0) translatedSubtitleBuilder.append(" · ")
                            translatedSubtitleBuilder.append(localizedText(subtitleParts[partIndex]))
                        }
                        val translatedSubtitle = translatedSubtitleBuilder.toString()
                        SettingsNavigationGroup(
                            modifier = Modifier.padding(vertical = 4.dp),
                            items = listOf(
                                SettingsNavigationItemData(
                                title = if (setting.route == Routes.LANGUAGE_SETTINGS) stringResource(R.string.language_settings) else localizedText(setting.title),
                                subtitle = if (setting.route == Routes.LANGUAGE_SETTINGS) {
                                    stringResource(R.string.language_settings_summary)
                                } else {
                                    translatedSubtitle
                                },
                                leadingIcon = setting.icon,
                                onClick = { onNavigateToRoute(setting.route) }
                                )
                            )
                        )
                    }
                }
                return@LazyColumn
            }
            SettingsSection.values().sortedBy { it.order }.forEach { section ->
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
