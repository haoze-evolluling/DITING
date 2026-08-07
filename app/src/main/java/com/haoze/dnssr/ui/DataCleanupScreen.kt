package com.haoze.dnssr.ui

import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.data.AppDatabase
import com.haoze.dnssr.data.entity.RuleScope
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsTextItem
import com.haoze.dnssr.vpn.AllowListManager
import com.haoze.dnssr.vpn.BlockListManager
import com.haoze.dnssr.vpn.RewriteRuleManager
import com.haoze.dnssr.vpn.BootstrapHealthEngine
import com.haoze.dnssr.vpn.BootstrapHealthStore
import com.haoze.dnssr.vpn.BootstrapLogger
import com.haoze.dnssr.vpn.DnsLogger
import com.haoze.dnssr.vpn.HttpRequestLogger
import com.haoze.dnssr.vpn.GoUrlRuleManager
import com.haoze.dnssr.vpn.ProviderHealthEngine
import com.haoze.dnssr.vpn.ProviderHealthStore
import com.haoze.dnssr.vpn.RaceLogger
import com.haoze.dnssr.vpn.cache.DnsCacheController
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun DataCleanupScreen(
    onBack: () -> Unit,
    title: String = "数据清理",
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    onExitApp: () -> Unit = {}
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    var pendingAction by remember { mutableStateOf<CleanupAction?>(null) }

    SettingsScaffold(
        title = localizedText(title),
        onBack = onBack
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(scrollState),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            SettingsInfoText(
                text = localizedText("以下操作会立即删除本机数据，删除后无法恢复。"),
                modifier = Modifier.padding(top = 8.dp)
            )

            SettingsGroupTitle(localizedText("运行数据"))
            SettingsSurfaceGroup(content = listOf(
                { SettingsTextItem(localizedText("删除请求日志"), subtitle = localizedText("清除 DNS 和 HTTP 的历史请求记录"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.LOG }) },
                { SettingsTextItem(localizedText("删除 DNS 缓存"), subtitle = localizedText("移除已缓存的解析结果，下次访问会重新查询"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.CACHE }) }
            ))

            SettingsGroupTitle(localizedText("权重数据"))
            SettingsSurfaceGroup(content = listOf(
                { SettingsTextItem(localizedText("恢复 DNS 默认权重"), subtitle = localizedText("清除智能选择的健康样本，让它重新按默认权重分配流量"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.PROVIDER_WEIGHT }) },
                { SettingsTextItem(localizedText("恢复 Bootstrap 权重"), subtitle = localizedText("清除 Bootstrap DNS 解析健康样本，重新按默认权重选择"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.BOOTSTRAP_WEIGHT }) }
            ))

            SettingsGroupTitle(localizedText("用户数据"))
            SettingsSurfaceGroup(content = listOf(
                { SettingsTextItem(localizedText("删除全部 DNS 规则"), subtitle = localizedText("清除 DNS 的域名屏蔽、白名单和覆写规则"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.DNS_RULES }) },
                { SettingsTextItem(localizedText("删除全部 HTTPS 过滤规则"), subtitle = localizedText("清除 Go 隧道的域名、URL、白名单和覆写规则"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.GO_TUNNEL_RULES }) },
                { SettingsTextItem(localizedText("重置所有新手引导"), subtitle = localizedText("让所有首次进入说明再次显示"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.SETTINGS_GUIDES }) }
            ))
        }
    }

    pendingAction?.let { action ->
        ConfirmDialog(
            title = action.title,
            text = action.message,
            onConfirm = {
                scope.launch(Dispatchers.IO) {
                    val db = AppDatabase.getInstance(context)
                    when (action) {
                        CleanupAction.CACHE -> {
                            DnsCacheController.clearAll(db.dnsCacheDao())
                        }
                        CleanupAction.LOG -> {
                            DnsLogger(db.dnsLogDao(), AppSettings.logRetentionDays(context)).clearAll()
                            HttpRequestLogger(db.httpRequestLogDao(), AppSettings.logRetentionDays(context)).clearAll()
                            RaceLogger(db.raceLogDao(), AppSettings.logRetentionDays(context)).clearAll()
                            BootstrapLogger(db.bootstrapLogDao(), AppSettings.logRetentionDays(context)).clearAll()
                        }
                        CleanupAction.PROVIDER_WEIGHT -> {
                            ProviderHealthEngine.flushActive(commit = true)
                            val providerIds = ProviderHealthStore.loadAll(context).keys
                            ProviderHealthStore.reset(context, providerIds)
                        }
                        CleanupAction.BOOTSTRAP_WEIGHT -> {
                            BootstrapHealthEngine.flushActive(commit = true)
                            val bootstrapIpIds = BootstrapHealthStore.loadAll(context).keys
                                .plus(AppSettings.loadBootstrapIpEntries(context).map { it.id })
                            BootstrapHealthStore.reset(context, bootstrapIpIds)
                        }
                        CleanupAction.DNS_RULES -> {
                            clearAllRules(context, RuleScope.DNS)
                        }
                        CleanupAction.GO_TUNNEL_RULES -> {
                            clearAllRules(context, RuleScope.HTTPS)
                        }
                        CleanupAction.SETTINGS_GUIDES -> {
                            AppSettings.resetAllSettingsGuides(context)
                        }
                    }
                    withContext(Dispatchers.Main) {
                        if (action == CleanupAction.DNS_RULES || action == CleanupAction.GO_TUNNEL_RULES) {
                            onRuntimeDnsSettingsChanged()
                        }
                        pendingAction = null
                        if (action == CleanupAction.SETTINGS_GUIDES) {
                            onExitApp()
                        } else {
                            Toast.makeText(context, localizedText(context, "已${action.title}"), Toast.LENGTH_SHORT).show()
                        }
                    }
                }
            },
            onDismiss = { pendingAction = null }
        )
    }
}

suspend fun clearAllRules(context: Context, scope: RuleScope) {
    val database = AppDatabase.getInstance(context)
    BlockListManager(database.blockRuleDao(), scope = scope).clearAll()
    AllowListManager(database.allowRuleDao(), scope = scope).clearAll()
    RewriteRuleManager(database.rewriteRuleDao(), java.io.File(context.filesDir, "rule-index"), scope).clearAll()
    if (scope == RuleScope.HTTPS) GoUrlRuleManager(database.goUrlRuleDao()).clearAll()
    database.subscriptionDao().resetAfterRuleCleanup(scope.storageValue)
}

private enum class CleanupAction(
    val title: String,
    val message: String
) {
    CACHE("删除 DNS 缓存", "确定要删除所有本地 DNS 缓存吗？下次访问域名时会重新查询。"),
    LOG("删除请求日志", "确定要删除所有 DNS、HTTP 请求日志、竞速统计和 Bootstrap DNS 解析统计吗？"),
    PROVIDER_WEIGHT("恢复竞速模式默认权重", "确定要清除所有服务商健康样本并恢复竞速模式默认权重吗？"),
    BOOTSTRAP_WEIGHT("恢复 Bootstrap IP 默认权重", "确定要清除 Bootstrap DNS 解析健康样本并恢复默认权重吗？"),
    DNS_RULES("删除全部 DNS 规则", "确定要删除全部 DNS 规则吗？域名屏蔽、白名单和覆写规则都会被移除。"),
    GO_TUNNEL_RULES("删除全部 HTTPS 过滤规则", "确定要删除全部 HTTPS 过滤规则吗？域名、URL、白名单和覆写规则都会被移除。"),
    SETTINGS_GUIDES("重置所有新手引导", "确定要重置所有应用设置新手引导和首次使用协议吗？这不会删除任何配置、规则、缓存、日志或证书。操作完成后应用将退出；下次打开时需要重新同意使用协议，所有新手引导也会再次显示。")
}

@Composable
fun ConfirmDialog(
    title: String,
    text: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(localizedText(title)) },
        text = { Text(localizedText(text)) },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(localizedText("确定")) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(localizedText("取消")) }
        }
    )
}
