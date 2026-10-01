package com.haoze.diting.ui.mode

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.LocalRippleConfiguration
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.SettingsItemSpacing
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.localizedText

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WorkModeSelectionScreen(
    isFirstLaunch: Boolean,
    currentMode: AppWorkMode = AppWorkMode.NORMAL,
    onBack: () -> Unit = {},
    onModeSelected: (AppWorkMode) -> Unit
) {
    CompositionLocalProvider(LocalRippleConfiguration provides null) {
        if (isFirstLaunch) {
            Scaffold(
                modifier = Modifier.fillMaxSize(),
                containerColor = Color.Transparent
            ) { innerPadding ->
                WorkModeSelectionContent(
                    isFirstLaunch = true,
                    currentMode = currentMode,
                    onModeSelected = onModeSelected,
                    modifier = Modifier
                        .padding(innerPadding)
                        .statusBarsPadding()
                )
            }
        } else {
            SettingsScaffold(
                title = "模式切换",
                onBack = onBack
            ) { innerPadding ->
                WorkModeSelectionContent(
                    isFirstLaunch = false,
                    currentMode = currentMode,
                    onModeSelected = onModeSelected,
                    modifier = Modifier.padding(innerPadding)
                )
            }
        }
    }
}

@Composable
private fun WorkModeSelectionContent(
    isFirstLaunch: Boolean,
    currentMode: AppWorkMode,
    onModeSelected: (AppWorkMode) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val alreadyInModeText = localizedText("当前已处于该模式")
    var pendingSwitchMode by remember { mutableStateOf<AppWorkMode?>(null) }

    if (pendingSwitchMode != null) {
        val targetMode = pendingSwitchMode!!
        AppConfirmDialog(
            onDismissRequest = { pendingSwitchMode = null },
            title = localizedText("确认切换运行模式"),
            message = localizedText("切换模式将重启网络服务并进入对应主界面，您的规则与配置均安全保留。确认切换吗？"),
            confirmLabel = localizedText("确认切换"),
            cancelLabel = localizedText("取消"),
            onConfirm = {
                pendingSwitchMode = null
                onModeSelected(targetMode)
            }
        )
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .navigationBarsPadding(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = if (isFirstLaunch) 32.dp else 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Column(
                modifier = Modifier.widthIn(max = 560.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Top Logo and Chinese + English Title
                WorkModeHeader()

                Spacer(modifier = Modifier.height(28.dp))

                // Mode Cards List (Stacked Gap-Divided Cards)
                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
                ) {
                    val modes = AppWorkMode.entries
                    modes.forEachIndexed { index, mode ->
                        val isSelected = !isFirstLaunch && mode == currentMode
                        WorkModeCard(
                            mode = mode,
                            isSelected = isSelected,
                            index = index,
                            itemCount = modes.size,
                            onClick = {
                                if (isFirstLaunch) {
                                    onModeSelected(mode)
                                } else if (isSelected) {
                                    Toast.makeText(context, alreadyInModeText, Toast.LENGTH_SHORT).show()
                                } else {
                                    pendingSwitchMode = mode
                                }
                            }
                        )
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}
