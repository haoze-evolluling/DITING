package com.haoze.diting.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.haoze.diting.ui.agent.AgentAnalysisSheet
import com.haoze.diting.ui.agent.AnalysisTarget
import com.haoze.diting.ui.components.AppAlertDialog
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.settings.AgentApiConfig
import com.haoze.diting.ui.settings.AgentApiPresetStore
import com.haoze.diting.ui.settings.AgentApiSettingsStore

enum class AgentApiSubPage {
    CREDENTIALS,
    PRESETS,
    PARAMS
}

/**
 * Agent API Settings Hub Screen.
 * Provides service authorization, status overview, categorized secondary sub-pages,
 * and live testing playground.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AgentApiSettingsScreen(
    onBack: () -> Unit,
    title: String = "AI 分析",
    onNavigate: (String) -> Unit = {},
    initialSubPage: AgentApiSubPage? = null
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var config by remember { mutableStateOf(AgentApiSettingsStore.getAgentApiConfig(context)) }
    var presets by remember { mutableStateOf(AgentApiPresetStore.getOrderedPresets(context)) }

    fun refreshState() {
        config = AgentApiSettingsStore.getAgentApiConfig(context)
        presets = AgentApiPresetStore.getOrderedPresets(context)
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                refreshState()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    LaunchedEffect(initialSubPage) {
        when (initialSubPage) {
            AgentApiSubPage.CREDENTIALS -> onNavigate(Routes.AGENT_API_CREDENTIALS)
            AgentApiSubPage.PRESETS -> onNavigate(Routes.AGENT_API_PRESETS)
            AgentApiSubPage.PARAMS -> onNavigate(Routes.AGENT_API_PARAMS)
            null -> Unit
        }
    }

    var showResetDialog by remember { mutableStateOf(false) }
    var activeAnalysisTarget by remember { mutableStateOf<AnalysisTarget?>(null) }

    fun updateConfig(newConfig: AgentApiConfig) {
        config = newConfig
        AgentApiSettingsStore.setAgentApiConfig(context, newConfig)
        presets = AgentApiPresetStore.getOrderedPresets(context)
    }

    val activePreset = presets.firstOrNull {
        it.baseUrl.equals(config.baseUrl, ignoreCase = true) &&
                it.model.equals(config.model, ignoreCase = true)
    }

    SettingsScaffold(title = localizedText(title), onBack = onBack) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            // 1. Service Master Switch & Status Overview
            item { SettingsGroupTitle(localizedText("服务状态")) }
            item {
                AgentApiStatusCard(
                    config = config,
                    activePreset = activePreset,
                    onEnabledChange = { enabled ->
                        updateConfig(config.copy(enabled = enabled))
                    }
                )
            }

            // 2. Secondary Settings Navigation Group
            item { SettingsGroupTitle(localizedText("详细设置")) }
            item {
                AgentApiNavigationGroup(
                    onNavigateToCredentials = { onNavigate(Routes.AGENT_API_CREDENTIALS) },
                    onNavigateToPresets = { onNavigate(Routes.AGENT_API_PRESETS) },
                    onNavigateToParams = { onNavigate(Routes.AGENT_API_PARAMS) }
                )
            }

            // 3. Live Playground
            item { SettingsGroupTitle(localizedText("功能测试")) }
            item {
                AgentApiPlaygroundCard(
                    onAnalyzeDomain = { domain ->
                        activeAnalysisTarget = AnalysisTarget.Domain(domain)
                    },
                    onAnalyzeTraffic = {
                        activeAnalysisTarget = AnalysisTarget.RecentTraffic()
                    }
                )
            }

            // 4. Reset & Maintenance
            item { SettingsGroupTitle(localizedText("重置设置")) }
            item {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                ) {
                    OutlinedButton(
                        onClick = { showResetDialog = true },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Filled.Refresh, contentDescription = null)
                        Spacer(modifier = Modifier.width(6.dp))
                        Text(localizedText("恢复出厂默认配置"))
                    }
                }
            }

            // 5. Informational notice
            item {
                AgentApiNoticeSection()
            }

            item { Spacer(modifier = Modifier.height(24.dp)) }
        }
    }

    // Reset confirmation dialog
    if (showResetDialog) {
        AppAlertDialog(
            onDismissRequest = { showResetDialog = false },
            title = { Text(localizedText("恢复默认配置？")) },
            text = { Text(localizedText("此操作将把所有 AI 分析参数、API Key 与系统提示词恢复为默认设置。")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        val defaultConfig = AgentApiConfig()
                        updateConfig(defaultConfig)
                        showResetDialog = false
                        Toast.makeText(context, "已恢复出厂配置", Toast.LENGTH_SHORT).show()
                    }
                ) {
                    Text(localizedText("确认恢复"))
                }
            },
            dismissButton = {
                TextButton(onClick = { showResetDialog = false }) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

    // Agent Analysis Sheet for live playground
    AgentAnalysisSheet(
        target = activeAnalysisTarget,
        onDismiss = { activeAnalysisTarget = null },
        onNavigateToSettings = {
            onNavigate(Routes.AGENT_API_CREDENTIALS)
        }
    )
}
