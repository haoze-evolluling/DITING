package com.haoze.diting.ui

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
import com.haoze.diting.data.cleanup.DataCleanupManager
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsTextItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun DataCleanupScreen(
    onBack: () -> Unit,
    title: String = "数据清理",
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    onExitApp: () -> Unit = {},
    dataset: com.haoze.diting.data.RuleDataset = com.haoze.diting.data.RuleDataset.NORMAL
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
                text = localizedText("以下操作会立即删除本机数据，删除后无法恢复。重要规则或配置请在执行前备份。"),
                modifier = Modifier.padding(top = 8.dp)
            )

            SettingsGroupTitle(localizedText("运行数据"))
            SettingsSurfaceGroup(content = listOf(
                { SettingsTextItem(localizedText("删除请求日志"), subtitle = localizedText("清除 DNS、HTTP 请求日志、竞速统计及 Bootstrap 解析日志"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.LOG }) },
                { SettingsTextItem(localizedText("删除流量统计"), subtitle = localizedText("清除所有应用的历史流量统计记录与实时统计状态"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.TRAFFIC }) },
                { SettingsTextItem(localizedText("删除崩溃日志"), subtitle = localizedText("清除本地保存的所有 Java 与 Native 异常崩溃日志"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.CRASH }) },
                { SettingsTextItem(localizedText("删除 DNS 缓存"), subtitle = localizedText("移除已缓存的解析结果，下次访问会重新查询"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.CACHE }) }
            ))

            SettingsGroupTitle(localizedText("权重数据"))
            SettingsSurfaceGroup(content = listOf(
                { SettingsTextItem(localizedText("恢复 DNS 默认权重"), subtitle = localizedText("清除智能选择的健康样本，让它重新按默认权重分配流量"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.PROVIDER_WEIGHT }) },
                { SettingsTextItem(localizedText("恢复 Bootstrap 权重"), subtitle = localizedText("清除 Bootstrap DNS 解析健康样本，重新按默认权重选择"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.BOOTSTRAP_WEIGHT }) }
            ))

            SettingsGroupTitle(localizedText("规则与订阅"))
            SettingsSurfaceGroup(content = listOf(
                { SettingsTextItem(localizedText("删除全部域名规则"), subtitle = localizedText("清除域名屏蔽、白名单、IPv4/IPv6 覆写及对应订阅，恢复预设白名单"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.DOMAIN_RULES }) },
                { SettingsTextItem(localizedText("删除全部地址规则"), subtitle = localizedText("清除 URL 屏蔽、放行和 CNAME 覆写规则，不影响域名规则"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.ADDRESS_RULES }) },
                { SettingsTextItem(localizedText("删除全部规则订阅"), subtitle = localizedText("清除所有网络与本地规则订阅、订阅分组及自动更新任务"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.SUBSCRIPTIONS }) },
                { SettingsTextItem(localizedText("重置应用控制名单"), subtitle = localizedText("清空分应用排除、禁止联网应用、应用白名单及抓包名单"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.APP_RULES }) }
            ))

            SettingsGroupTitle(localizedText("存储与安全"))
            SettingsSurfaceGroup(content = listOf(
                { SettingsTextItem(localizedText("重置出站代理配置"), subtitle = localizedText("清空出站代理协议、服务器与鉴权信息，恢复直连"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.OUTBOUND_PROXY }) },
                { SettingsTextItem(localizedText("重置 HTTPS 抓包证书"), subtitle = localizedText("清除本地生成的 MITM CA 根证书与私钥"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.CA_CERTIFICATE }) },
                { SettingsTextItem(localizedText("清理下载与临时缓存"), subtitle = localizedText("删除更新安装包、下载临时文件及应用临时缓存"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.DOWNLOAD_CACHE }) },
                { SettingsTextItem(localizedText("清除自定义背景缓存"), subtitle = localizedText("清除已配置的自定义壁纸图片缓存及路径记录，恢复默认背景"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.CUSTOM_BACKGROUND }) }
            ))

            SettingsGroupTitle(localizedText("引导与重置"))
            SettingsSurfaceGroup(content = listOf(
                { SettingsTextItem(localizedText("重置所有新手引导"), subtitle = localizedText("让所有首次进入说明再次显示，需要重新同意使用协议"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.SETTINGS_GUIDES }) },
                { SettingsTextItem(localizedText("清理全部本地数据"), subtitle = localizedText("深度清空所有日志、缓存、规则、订阅、证书与配置，应用将退出"), textColor = MaterialTheme.colorScheme.error, onClick = { pendingAction = CleanupAction.ALL_DATA }) }
            ))
        }
    }

    pendingAction?.let { action ->
        ConfirmDialog(
            title = action.title,
            text = action.message,
            onConfirm = {
                scope.launch(Dispatchers.IO) {
                    when (action) {
                        CleanupAction.LOG -> DataCleanupManager.clearRequestLogs(context, dataset = dataset)
                        CleanupAction.TRAFFIC -> DataCleanupManager.clearTrafficStats(context)
                        CleanupAction.CRASH -> DataCleanupManager.clearCrashLogs(context)
                        CleanupAction.CACHE -> DataCleanupManager.clearDnsCache(context, dataset = dataset)
                        CleanupAction.PROVIDER_WEIGHT -> DataCleanupManager.resetProviderWeights(context)
                        CleanupAction.BOOTSTRAP_WEIGHT -> DataCleanupManager.resetBootstrapWeights(context)
                        CleanupAction.DOMAIN_RULES -> DataCleanupManager.clearAllDomainRules(context, dataset = dataset)
                        CleanupAction.ADDRESS_RULES -> DataCleanupManager.clearAllAddressRules(context, dataset = dataset)
                        CleanupAction.SUBSCRIPTIONS -> DataCleanupManager.clearAllSubscriptions(context, dataset = dataset)
                        CleanupAction.APP_RULES -> DataCleanupManager.resetAppRules(context)
                        CleanupAction.OUTBOUND_PROXY -> DataCleanupManager.resetOutboundProxy(context)
                        CleanupAction.CA_CERTIFICATE -> DataCleanupManager.resetCaCertificate(context)
                        CleanupAction.DOWNLOAD_CACHE -> DataCleanupManager.clearDownloadAndTempCache(context)
                        CleanupAction.CUSTOM_BACKGROUND -> DataCleanupManager.clearCustomBackground(context)
                        CleanupAction.SETTINGS_GUIDES -> DataCleanupManager.resetSettingsGuides(context)
                        CleanupAction.ALL_DATA -> DataCleanupManager.clearAllLocalData(context, dataset = dataset)
                    }
                    withContext(Dispatchers.Main) {
                        when (action) {
                            CleanupAction.DOMAIN_RULES,
                            CleanupAction.ADDRESS_RULES,
                            CleanupAction.SUBSCRIPTIONS,
                            CleanupAction.APP_RULES,
                            CleanupAction.OUTBOUND_PROXY -> {
                                onRuntimeDnsSettingsChanged()
                                context.showToast("已${action.title}", Toast.LENGTH_SHORT)
                            }
                            CleanupAction.SETTINGS_GUIDES,
                            CleanupAction.ALL_DATA -> {
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

private enum class CleanupAction(
    val title: String,
    val message: String
) {
    LOG(
        "删除请求日志",
        "确定要删除所有 DNS、HTTP 请求日志、竞速统计和 Bootstrap DNS 解析统计吗？"
    ),
    TRAFFIC(
        "删除流量统计",
        "确定要清除所有应用的历史流量统计记录与实时统计状态吗？"
    ),
    CRASH(
        "删除崩溃日志",
        "确定要删除所有本地崩溃日志和崩溃统计状态吗？"
    ),
    CACHE(
        "删除 DNS 缓存",
        "确定要删除所有本地 DNS 缓存吗？下次访问域名时会重新查询。"
    ),
    PROVIDER_WEIGHT(
        "恢复竞速模式默认权重",
        "确定要清除所有服务商健康样本并恢复竞速模式默认权重吗？"
    ),
    BOOTSTRAP_WEIGHT(
        "恢复 Bootstrap IP 默认权重",
        "确定要清除 Bootstrap DNS 解析健康样本并恢复默认权重吗？"
    ),
    DOMAIN_RULES(
        "删除全部域名规则",
        "确定要删除全部域名规则吗？域名屏蔽、白名单、IPv4/IPv6 覆写规则及对应订阅都会被移除，地址规则不受影响。"
    ),
    ADDRESS_RULES(
        "删除全部地址规则",
        "确定要删除全部地址规则吗？URL 屏蔽、放行和 CNAME 覆写规则都会被移除，域名规则不受影响。"
    ),
    SUBSCRIPTIONS(
        "删除全部规则订阅",
        "确定要删除所有规则订阅吗？所有订阅链接、分组与订阅导入的规则都会被移除，手动添加的规则不受影响。"
    ),
    APP_RULES(
        "重置应用控制名单",
        "确定要重置所有应用控制名单吗？分应用代理排除、禁止联网应用、应用独立白名单以及 HTTP/HTTPS 抓包应用配置都将被清空并恢复默认。"
    ),
    OUTBOUND_PROXY(
        "重置出站代理配置",
        "确定要重置出站代理配置吗？出站代理将被禁用，服务器地址、端口及账号密码将被清除。"
    ),
    CA_CERTIFICATE(
        "重置 HTTPS 抓包证书",
        "确定要清除本地生成的 HTTPS 抓包 CA 证书和私钥吗？如果系统已安装此证书，清除后需重新生成并导入系统方可继续解密抓包。"
    ),
    DOWNLOAD_CACHE(
        "清理下载与临时缓存",
        "确定要删除下载的更新安装包和临时缓存文件吗？"
    ),
    CUSTOM_BACKGROUND(
        "清除自定义背景缓存",
        "确定要清除自定义壁纸缓存并恢复默认外观背景吗？"
    ),
    SETTINGS_GUIDES(
        "重置所有新手引导",
        "确定要重置所有应用设置新手引导和首次使用协议吗？这不会删除任何配置、规则、缓存、日志或证书。操作完成后应用将退出；下次打开时需要重新同意使用协议，所有新手引导也会再次显示。"
    ),
    ALL_DATA(
        "清理全部本地数据",
        "确定要执行全面数据清理吗？将依次清理所有日志、流量统计、崩溃记录、DNS 缓存、服务商权重、域名及地址规则、规则订阅、临时缓存及抓包证书。所有自定义配置与规则将被清空，新手引导也将重置，操作完成后应用将退出。"
    )
}

@Composable
fun ConfirmDialog(
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
