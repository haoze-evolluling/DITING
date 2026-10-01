package com.haoze.diting.ui.mode

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
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
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.localizedText

/**
 * Modernized Work Mode Selection & Switching screen.
 * Handles both first-launch onboarding and settings-based mode switching flows.
 */
@Composable
fun WorkModeSelectionScreen(
    isFirstLaunch: Boolean,
    currentMode: AppWorkMode = AppWorkMode.NORMAL,
    onBack: () -> Unit = {},
    onModeSelected: (AppWorkMode) -> Unit
) {
    if (isFirstLaunch) {
        Scaffold(
            modifier = Modifier.fillMaxSize(),
            containerColor = Color.Transparent
        ) { innerPadding ->
            FirstLaunchWorkModeContent(
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
            SettingsWorkModeContent(
                currentMode = currentMode,
                onModeSelected = onModeSelected,
                modifier = Modifier.padding(innerPadding)
            )
        }
    }
}

/**
 * Settings context content: Displays the active profile hero, mode options, and capability comparison.
 */
@Composable
private fun SettingsWorkModeContent(
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
        contentAlignment = Alignment.TopCenter
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 600.dp)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            // Active Mode Hero Card
            WorkModeCurrentStatusHero(currentMode = currentMode)

            Text(
                text = localizedText("可选工作模式"),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.padding(top = 4.dp, start = 2.dp)
            )

            // Mode Option Cards
            AppWorkMode.entries.forEach { mode ->
                val isCurrent = mode == currentMode
                WorkModeCard(
                    mode = mode,
                    isSelected = isCurrent,
                    onClick = {
                        if (isCurrent) {
                            Toast.makeText(
                                context,
                                alreadyInModeText,
                                Toast.LENGTH_SHORT
                            ).show()
                        } else {
                            pendingSwitchMode = mode
                        }
                    }
                )
            }

            Spacer(modifier = Modifier.height(4.dp))

            // Technical Capability Comparison Section
            WorkModeComparisonSection()

            Spacer(modifier = Modifier.height(16.dp))
        }
    }
}

/**
 * First-launch onboarding content: Introduces the two modes and allows clear initial selection.
 */
@Composable
private fun FirstLaunchWorkModeContent(
    currentMode: AppWorkMode,
    onModeSelected: (AppWorkMode) -> Unit,
    modifier: Modifier = Modifier
) {
    var selectedCandidate by remember { mutableStateOf(currentMode) }

    Box(
        modifier = modifier
            .fillMaxSize()
            .navigationBarsPadding(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 580.dp)
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.SpaceBetween
        ) {
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(18.dp)
            ) {
                WorkModeOnboardingHero()

                Spacer(modifier = Modifier.height(8.dp))

                AppWorkMode.entries.forEach { mode ->
                    WorkModeCard(
                        mode = mode,
                        isSelected = mode == selectedCandidate,
                        onClick = { selectedCandidate = mode }
                    )
                }

                WorkModeComparisonSection()
            }

            Spacer(modifier = Modifier.height(24.dp))

            Button(
                onClick = { onModeSelected(selectedCandidate) },
                shape = SettingsCornerShape,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(50.dp)
            ) {
                Text(
                    text = localizedText("以此模式开启体验"),
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.SemiBold
                )
            }
        }
    }
}
