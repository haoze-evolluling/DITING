package com.haoze.dnssr.ui

import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.RadioButton
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LanguageSettingsScreen(onBack: () -> Unit, onLanguageChanged: (AppLanguageMode) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    var selectedMode by remember { mutableStateOf(AppLanguageManager.getMode(context)) }

    SettingsScaffold(title = stringResource(R.string.language_settings), onBack = onBack) { padding ->
        androidx.compose.foundation.layout.Column(Modifier.padding(padding)) {
            SettingsInfoText(stringResource(R.string.language_settings_summary))
            SettingsSurfaceGroup(
                content = listOf(
                    {
                        LanguageOption(AppLanguageMode.SYSTEM, selectedMode) {
                            selectedMode = it
                            onLanguageChanged(it)
                        }
                    },
                    {
                        LanguageOption(AppLanguageMode.CHINESE, selectedMode) {
                            selectedMode = it
                            onLanguageChanged(it)
                        }
                    },
                    {
                        LanguageOption(AppLanguageMode.ENGLISH, selectedMode) {
                            selectedMode = it
                            onLanguageChanged(it)
                        }
                    }
                )
            )
        }
    }
}

@Composable
private fun LanguageOption(
    mode: AppLanguageMode,
    selectedMode: AppLanguageMode,
    onSelected: (AppLanguageMode) -> Unit
) {
    val title = when (mode) {
        AppLanguageMode.SYSTEM -> stringResource(R.string.language_follow_system)
        AppLanguageMode.CHINESE -> stringResource(R.string.language_chinese)
        AppLanguageMode.ENGLISH -> stringResource(R.string.language_english)
    }
    SettingsItem(
        title = title,
        onClick = { onSelected(mode) },
        trailing = {
            RadioButton(selected = selectedMode == mode, onClick = { onSelected(mode) })
        }
    )
}
