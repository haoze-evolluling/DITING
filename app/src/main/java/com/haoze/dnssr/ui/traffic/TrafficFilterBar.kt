package com.haoze.dnssr.ui.traffic

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.localizedText

@Composable
internal fun TrafficFilterBar(
    uiState: AppTrafficStatsUiState,
    onSearchChange: (String) -> Unit,
    onSortChange: (TrafficSortMode) -> Unit,
    onHideSystemAppsChange: (Boolean) -> Unit
) {
    val colors = MaterialTheme.colorScheme
    var sortMenuExpanded by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        OutlinedTextField(
            value = uiState.searchQuery,
            onValueChange = onSearchChange,
            placeholder = { Text(localizedText("搜索应用或包名...")) },
            leadingIcon = {
                Icon(
                    imageVector = Icons.Default.Search,
                    contentDescription = null,
                    tint = colors.onSurfaceVariant
                )
            },
            trailingIcon = {
                if (uiState.searchQuery.isNotEmpty()) {
                    IconButton(onClick = { onSearchChange("") }) {
                        Icon(
                            imageVector = Icons.Default.Clear,
                            contentDescription = localizedText("清除")
                        )
                    }
                }
            },
            shape = SettingsCornerShape,
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = colors.outlineVariant.copy(alpha = 0.5f)
            ),
            singleLine = true,
            modifier = Modifier.fillMaxWidth()
        )

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box {
                FilterChip(
                    selected = true,
                    onClick = { sortMenuExpanded = true },
                    label = { Text(localizedText(uiState.selectedSortMode.displayName)) },
                    leadingIcon = {
                        Icon(
                            imageVector = Icons.Default.FilterList,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp)
                        )
                    },
                    shape = SettingsCornerShape,
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = colors.surfaceVariant.copy(alpha = 0.7f)
                    )
                )

                DropdownMenu(
                    expanded = sortMenuExpanded,
                    onDismissRequest = { sortMenuExpanded = false }
                ) {
                    TrafficSortMode.entries.forEach { mode ->
                        DropdownMenuItem(
                            text = { Text(localizedText(mode.displayName)) },
                            onClick = {
                                onSortChange(mode)
                                sortMenuExpanded = false
                            }
                        )
                    }
                }
            }

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp)
            ) {
                Text(
                    text = localizedText("隐藏系统应用"),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.onSurfaceVariant
                )
                Switch(
                    checked = uiState.hideSystemApps,
                    onCheckedChange = onHideSystemAppsChange
                )
            }
        }
    }
}
