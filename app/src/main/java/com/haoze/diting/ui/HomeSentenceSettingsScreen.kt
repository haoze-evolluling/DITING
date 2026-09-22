package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.SettingsActionButton
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.settings.AppearanceSettingsStore

@Composable
fun HomeSentenceSettingsScreen(onBack: () -> Unit, title: String) {
    val context = LocalContext.current
    var runningSentence by remember { mutableStateOf(AppearanceSettingsStore.getHomeSentenceRunning(context)) }
    var stoppedSentence by remember { mutableStateOf(AppearanceSettingsStore.getHomeSentenceStopped(context)) }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item { SettingsGroupTitle(localizedText("首页句子")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf {
                        Column(
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            OutlinedTextField(
                                value = runningSentence,
                                onValueChange = { runningSentence = it },
                                label = { Text(localizedText("DNS 服务开启时")) },
                                minLines = 2,
                                shape = SettingsCornerShape,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 16.dp, top = 16.dp, end = 16.dp)
                            )
                            OutlinedTextField(
                                value = stoppedSentence,
                                onValueChange = { stoppedSentence = it },
                                label = { Text(localizedText("DNS 服务关闭时")) },
                                minLines = 2,
                                shape = SettingsCornerShape,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(16.dp)
                            )
                            SettingsActionButton(
                                onClick = {
                                    AppearanceSettingsStore.setHomeSentences(context, runningSentence, stoppedSentence)
                                    onBack()
                                },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(start = 16.dp, end = 16.dp, bottom = 16.dp)
                            ) {
                                Text(localizedText("确定"))
                            }
                        }
                    }
                )
            }
            item { SettingsInfoText(localizedText("两项内容均可留空；留空后对应状态下首页不显示句子。")) }
        }
    }
}
