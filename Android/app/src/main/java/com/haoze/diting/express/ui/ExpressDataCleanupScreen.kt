package com.haoze.diting.express.ui

import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.cleanup.DataCleanupManager
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsTextItem
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.showToast
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Dedicated Data Cleanup Screen for Express Mode.
 *
 * Physically omits full-tunnel cleanup actions:
 * - Delete traffic stats (App traffic stats)
 * - Delete address rules (URL & CNAME rules)
 * - Reset app control rules (Blocked apps & per-app rules)
 * - Reset outbound proxy (SOCKS5/HTTP proxy)
 * - Reset HTTPS inspection certificate (CA certificate & MITM)
 */
@Composable
fun ExpressDataCleanupScreen(
    onBack: () -> Unit,
    title: String = "数据清理",
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    onExitApp: () -> Unit = {}
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val scrollState = rememberScrollState()

    var pendingAction by remember { mutableStateOf<ExpressCleanupAction?>(null) }

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
                text = localizedText("以下操作会立即删除本机数据，删除后无法恢复。重要规则或配置请在执行前备份。"),
                modifier = Modifier.padding(top = 8.dp)
            )

            // 1. 运行数据 (3 项: 请求日志、崩溃日志、DNS 缓存; 流量统计已移除)
            SettingsGroupTitle(localizedText("运行数据"))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.LOG.title),
                        subtitle = localizedText("清除 DNS 请求日志、竞速统计及 Bootstrap 解析日志"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.LOG }
                    )
                },
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.CRASH.title),
                        subtitle = localizedText("清除本地保存的所有 Java 与 Native 异常崩溃日志"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.CRASH }
                    )
                },
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.CACHE.title),
                        subtitle = localizedText("移除已缓存的解析结果，下次访问会重新查询"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.CACHE }
                    )
                }
            ))

            // 2. 权重数据 (2 项: 恢复 DNS 默认权重、恢复 Bootstrap 权重)
            SettingsGroupTitle(localizedText("权重数据"))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.PROVIDER_WEIGHT.title),
                        subtitle = localizedText("清除智能选择的健康样本，让它重新按默认权重分配流量"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.PROVIDER_WEIGHT }
                    )
                },
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.BOOTSTRAP_WEIGHT.title),
                        subtitle = localizedText("清除 Bootstrap DNS 解析健康样本，重新按默认权重选择"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.BOOTSTRAP_WEIGHT }
                    )
                }
            ))

            // 3. 规则与订阅 (2 项: 删除全部域名规则、删除全部规则订阅; 地址规则与应用控制名单已移除)
            SettingsGroupTitle(localizedText("规则与订阅"))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.DOMAIN_RULES.title),
                        subtitle = localizedText("清除域名屏蔽、白名单及对应订阅，恢复预设白名单"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.DOMAIN_RULES }
                    )
                },
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.SUBSCRIPTIONS.title),
                        subtitle = localizedText("清除所有网络与本地规则订阅、订阅分组及自动更新任务"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.SUBSCRIPTIONS }
                    )
                }
            ))

            // 4. 存储与安全 (2 项: 清理下载与临时缓存、清除自定义背景缓存; 出站代理与抓包证书已移除)
            SettingsGroupTitle(localizedText("存储与安全"))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.DOWNLOAD_CACHE.title),
                        subtitle = localizedText("删除更新安装包、下载临时文件及应用临时缓存"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.DOWNLOAD_CACHE }
                    )
                },
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.CUSTOM_BACKGROUND.title),
                        subtitle = localizedText("清除已配置的自定义壁纸图片缓存及路径记录，恢复默认背景"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.CUSTOM_BACKGROUND }
                    )
                }
            ))

            // 5. 引导与重置 (2 项: 重置所有新手引导、清理全部本地数据)
            SettingsGroupTitle(localizedText("引导与重置"))
            SettingsSurfaceGroup(content = listOf(
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.SETTINGS_GUIDES.title),
                        subtitle = localizedText("让所有首次进入说明再次显示，需要重新同意使用协议"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.SETTINGS_GUIDES }
                    )
                },
                {
                    SettingsTextItem(
                        title = localizedText(ExpressCleanupAction.ALL_DATA.title),
                        subtitle = localizedText("深度清空所有日志、缓存、规则、订阅与配置，应用将退出"),
                        textColor = MaterialTheme.colorScheme.error,
                        onClick = { pendingAction = ExpressCleanupAction.ALL_DATA }
                    )
                }
            ))
        }
    }

    pendingAction?.let { action ->
        ExpressConfirmDialog(
            title = localizedText(action.title),
            text = localizedText(action.message),
            onConfirm = {
                scope.launch(Dispatchers.IO) {
                    when (action) {
                        ExpressCleanupAction.LOG -> DataCleanupManager.clearRequestLogs(context, dataset = RuleDataset.EXPRESS)
                        ExpressCleanupAction.CRASH -> DataCleanupManager.clearCrashLogs(context)
                        ExpressCleanupAction.CACHE -> DataCleanupManager.clearDnsCache(context, dataset = RuleDataset.EXPRESS)
                        ExpressCleanupAction.PROVIDER_WEIGHT -> DataCleanupManager.resetProviderWeights(context)
                        ExpressCleanupAction.BOOTSTRAP_WEIGHT -> DataCleanupManager.resetBootstrapWeights(context)
                        ExpressCleanupAction.DOMAIN_RULES -> DataCleanupManager.clearAllDomainRules(context, dataset = RuleDataset.EXPRESS)
                        ExpressCleanupAction.SUBSCRIPTIONS -> DataCleanupManager.clearAllSubscriptions(context, dataset = RuleDataset.EXPRESS)
                        ExpressCleanupAction.DOWNLOAD_CACHE -> DataCleanupManager.clearDownloadAndTempCache(context)
                        ExpressCleanupAction.CUSTOM_BACKGROUND -> DataCleanupManager.clearCustomBackground(context)
                        ExpressCleanupAction.SETTINGS_GUIDES -> DataCleanupManager.resetSettingsGuides(context)
                        ExpressCleanupAction.ALL_DATA -> DataCleanupManager.clearAllLocalData(context, dataset = RuleDataset.EXPRESS)
                    }
                    withContext(Dispatchers.Main) {
                        when (action) {
                            ExpressCleanupAction.DOMAIN_RULES,
                            ExpressCleanupAction.SUBSCRIPTIONS -> {
                                onRuntimeDnsSettingsChanged()
                                context.showToast("已${action.title}", Toast.LENGTH_SHORT)
                            }
                            ExpressCleanupAction.SETTINGS_GUIDES,
                            ExpressCleanupAction.ALL_DATA -> {
                                onExitApp()
                            }
                            else -> {
                                context.showToast("已${action.title}", Toast.LENGTH_SHORT)
                            }
                        }
                        pendingAction = null
                    }
                }
            },
            onDismiss = { pendingAction = null }
        )
    }
}

enum class ExpressCleanupAction(
    val title: String,
    val message: String
) {
    LOG(
        title = "删除请求日志",
        message = "确定要删除所有 DNS 请求日志、竞速统计和 Bootstrap DNS 解析统计吗？"
    ),
    CRASH(
        title = "删除崩溃日志",
        message = "确定要删除所有本地崩溃日志和崩溃统计状态吗？"
    ),
    CACHE(
        title = "删除 DNS 缓存",
        message = "确定要删除所有本地 DNS 缓存吗？下次访问域名时会重新查询。"
    ),
    PROVIDER_WEIGHT(
        title = "恢复竞速模式默认权重",
        message = "确定要清除所有服务商健康样本并恢复竞速模式默认权重吗？"
    ),
    BOOTSTRAP_WEIGHT(
        title = "恢复 Bootstrap IP 默认权重",
        message = "确定要清除 Bootstrap DNS 解析健康样本并恢复默认权重吗？"
    ),
    DOMAIN_RULES(
        title = "删除全部域名规则",
        message = "确定要删除全部域名规则吗？域名屏蔽、白名单及对应订阅都会被移除。"
    ),
    SUBSCRIPTIONS(
        title = "删除全部规则订阅",
        message = "确定要删除所有规则订阅吗？所有订阅链接、分组与订阅导入的规则都会被移除，手动添加的规则不受影响。"
    ),
    DOWNLOAD_CACHE(
        title = "清理下载与临时缓存",
        message = "确定要删除下载的更新安装包和临时缓存文件吗？"
    ),
    CUSTOM_BACKGROUND(
        title = "清除自定义背景缓存",
        message = "确定要清除自定义壁纸缓存并恢复默认外观背景吗？"
    ),
    SETTINGS_GUIDES(
        title = "重置所有新手引导",
        message = "确定要重置所有应用设置新手引导和首次使用协议吗？这不会删除任何配置、规则、缓存或日志。操作完成后应用将退出；下次打开时需要重新同意使用协议，所有新手引导也会再次显示。"
    ),
    ALL_DATA(
        title = "清理全部本地数据",
        message = "确定要执行全面数据清理吗？将依次清理所有日志、崩溃记录、DNS 缓存、服务商权重、域名规则、规则订阅及临时缓存。所有自定义配置与规则将被清空，新手引导也将重置，操作完成后应用将退出。"
    )
}

@Composable
private fun ExpressConfirmDialog(
    title: String,
    text: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit
) {
    AppConfirmDialog(
        onDismissRequest = onDismiss,
        title = title,
        message = text,
        confirmLabel = "确定",
        onConfirm = {
            onConfirm()
            onDismiss()
        },
        destructive = true
    )
}
