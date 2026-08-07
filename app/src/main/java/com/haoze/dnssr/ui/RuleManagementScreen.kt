package com.haoze.dnssr.ui

import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsScaffold
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import com.haoze.dnssr.data.entity.RewriteTargetType
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.data.entity.RuleScope

@Composable
fun RuleManagementScreen(
    onBack: () -> Unit,
    ruleScope: RuleScope = RuleScope.DNS,
    title: String = "域名规则",
    onNavigateToRuleList: () -> Unit,
    onNavigateToAllowRuleList: () -> Unit,
    onNavigateToRewriteRuleList: () -> Unit,
    onNavigateToUrlRuleList: () -> Unit,
    onNavigateToUrlAllowRuleList: () -> Unit,
    onNavigateToSubscription: () -> Unit,
    onNavigateToMirrorTemplates: () -> Unit,
    onNavigateToAutoUpdateInterval: () -> Unit,
    onNavigateToBlockResponseSettings: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    viewModel: RuleManagementViewModel = viewModel()
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val lifecycleOwner = LocalLifecycleOwner.current
    val ruleCount by viewModel.ruleCount.collectAsStateWithLifecycle()
    val allowRuleCount by viewModel.allowRuleCount.collectAsStateWithLifecycle()
    val rewriteRuleCount by viewModel.rewriteRuleCount.collectAsStateWithLifecycle()
    val urlRuleCount by viewModel.urlRuleCount.collectAsStateWithLifecycle()
    val urlAllowRuleCount by viewModel.urlAllowRuleCount.collectAsStateWithLifecycle()
    val mirrorTemplates by viewModel.mirrorTemplates.collectAsStateWithLifecycle(initialValue = emptyList())

    var newRule by remember { mutableStateOf("") }
    var newAllowRule by remember { mutableStateOf("") }
    var newUrlRule by remember { mutableStateOf("") }
    var rewriteDomain by remember { mutableStateOf("") }
    var rewriteAddress by remember { mutableStateOf("") }
    var rewriteTargetType by remember { mutableStateOf(RewriteTargetType.IPV4) }
    var addResult by remember { mutableStateOf<String?>(null) }
    var addAllowResult by remember { mutableStateOf<String?>(null) }
    var showAddRuleDialog by remember { mutableStateOf(false) }
    var showAddAllowRuleDialog by remember { mutableStateOf(false) }
    var showAddUrlRuleDialog by remember { mutableStateOf(false) }
    var showAddUrlAllowRuleDialog by remember { mutableStateOf(false) }
    var showAddRewriteRuleDialog by remember { mutableStateOf(false) }
    var showClearAllRulesDialog by remember { mutableStateOf(false) }
    var addRuleError by remember { mutableStateOf<String?>(null) }
    var addAllowRuleError by remember { mutableStateOf<String?>(null) }
    var addRewriteRuleError by remember { mutableStateOf<String?>(null) }

    fun openAddRuleDialog() {
        newRule = ""
        addRuleError = null
        showAddRuleDialog = true
    }

    fun closeAddRuleDialog() {
        showAddRuleDialog = false
        addRuleError = null
    }

    fun openAddAllowRuleDialog() {
        newAllowRule = ""
        addAllowRuleError = null
        showAddAllowRuleDialog = true
    }

    fun closeAddAllowRuleDialog() {
        showAddAllowRuleDialog = false
        addAllowRuleError = null
    }

    fun openAddRewriteRuleDialog() {
        rewriteDomain = ""
        rewriteAddress = ""
        rewriteTargetType = if (ruleScope == RuleScope.DNS) RewriteTargetType.IPV4 else RewriteTargetType.CNAME
        addRewriteRuleError = null
        showAddRewriteRuleDialog = true
    }

    fun closeAddRewriteRuleDialog() {
        showAddRewriteRuleDialog = false
        addRewriteRuleError = null
    }

    NavigationSettledEffect(ruleScope) {
        viewModel.activate(ruleScope)
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.loadRuleCount()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    SettingsScaffold(
        title = localizedText(title),
        onBack = onBack
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            item {
                SettingsInfoText(
                    text = localizedText(if (ruleScope == RuleScope.DNS) "当前共有 $ruleCount 条屏蔽规则，$allowRuleCount 条白名单规则，$rewriteRuleCount 条 IPv4/IPv6 覆写规则。覆写规则优先于黑白名单。" else "仅在 HTTPS 流量检查可解密的 HTTP(S) 请求中生效。域名规则 $ruleCount/$allowRuleCount 条，URL 屏蔽/放行规则 $urlRuleCount/$urlAllowRuleCount 条，CNAME 覆写 $rewriteRuleCount 条。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            if (ruleScope == RuleScope.DNS) item {
                SettingsGroupTitle(localizedText("拦截策略"))
            }
            if (ruleScope == RuleScope.DNS) item {
                val dynamicConfig = AppSettings.getDynamicBlockResponseConfig(context)
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("拦截响应"),
                        subtitle = localizedText(if (dynamicConfig.enabled) {
                            "动态策略：先 NODATA，高频请求后 NXDOMAIN"
                        } else {
                            localizedText("当前：${localizedText(AppSettings.getBlockResponseMode(context).displayName)}")
                        }),
                        onClick = onNavigateToBlockResponseSettings
                        )
                    )
                )
            }

            if (ruleScope == RuleScope.HTTPS) item {
                SettingsGroupTitle(localizedText("URL 请求规则"))
            }
            if (ruleScope == RuleScope.HTTPS) item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(title = localizedText("添加屏蔽 URL"), subtitle = localizedText("如 https://example.com/js，匹配该路径前缀"), onClick = { newUrlRule = ""; showAddUrlRuleDialog = true }),
                        SettingsNavigationItemData(title = localizedText("添加放行 URL"), subtitle = localizedText("如 https://example.com/allowed，可覆盖域名屏蔽"), onClick = { newUrlRule = ""; showAddUrlAllowRuleDialog = true }),
                        SettingsNavigationItemData(title = localizedText("URL 屏蔽规则"), subtitle = localizedText("查看、启用、停用或删除 URL 屏蔽规则"), value = localizedText("$urlRuleCount 条"), onClick = onNavigateToUrlRuleList),
                        SettingsNavigationItemData(title = localizedText("URL 放行规则"), subtitle = localizedText("查看、启用、停用或删除 URL 放行规则"), value = localizedText("$urlAllowRuleCount 条"), onClick = onNavigateToUrlAllowRuleList)
                    )
                )
            }

            item {
                SettingsGroupTitle(localizedText("域名屏蔽与放行"))
            }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("添加屏蔽域名"),
                        subtitle = localizedText("输入要屏蔽的域名，如 example.com"),
                        onClick = ::openAddRuleDialog
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("添加放行域名"),
                        subtitle = localizedText("输入要放行的域名，如 example.com"),
                        onClick = ::openAddAllowRuleDialog
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("黑名单规则"),
                        subtitle = localizedText("查看、启用、停用或删除屏蔽规则"),
                        value = localizedText("$ruleCount 条"),
                        onClick = onNavigateToRuleList
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("白名单规则"),
                        subtitle = localizedText("查看、启用、停用或删除放行规则"),
                        value = localizedText("$allowRuleCount 条"),
                        onClick = onNavigateToAllowRuleList
                        )
                    )
                )
            }

            item {
                SettingsGroupTitle(localizedText(if (ruleScope == RuleScope.DNS) "域名覆写" else "CNAME 覆写"))
            }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("添加覆写域名"),
                        subtitle = localizedText(if (ruleScope == RuleScope.DNS) "将域名覆写为 IPv4 或 IPv6" else "将域名覆写为 CNAME"),
                        onClick = ::openAddRewriteRuleDialog
                        ),
                        SettingsNavigationItemData(
                        title = localizedText(if (ruleScope == RuleScope.DNS) "IPv4/IPv6 覆写规则" else "CNAME 覆写规则"),
                        subtitle = localizedText("查看、启用、停用或删除当前范围的覆写规则"),
                        value = localizedText("$rewriteRuleCount 条"),
                        onClick = onNavigateToRewriteRuleList
                        )
                    )
                )
            }
            addResult?.let { message ->
                item {
                    SettingsInfoText(localizedText(message))
                }
            }
            addAllowResult?.let { message ->
                item {
                    SettingsInfoText(localizedText(message))
                }
            }

            item {
                SettingsGroupTitle(localizedText("订阅与更新"))
            }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText("规则订阅"),
                        subtitle = localizedText(if (ruleScope == RuleScope.DNS) "管理 DNS 域名规则与 IPv4/IPv6 覆写订阅" else "管理 HTTPS 域名、URL 与 CNAME 覆写订阅"),
                        onClick = onNavigateToSubscription
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("自动更新设置"),
                        subtitle = localizedText("设置规则订阅的自动更新开关和频率"),
                        onClick = onNavigateToAutoUpdateInterval
                        ),
                        SettingsNavigationItemData(
                        title = localizedText("镜像站模板"),
                        subtitle = localizedText("维护订阅下载镜像，可在添加订阅时直接选择"),
                        value = localizedText("${mirrorTemplates.size} 个"),
                        onClick = {
                            onNavigateToMirrorTemplates()
                        }
                        )
                    )
                )
            }

            item {
                SettingsGroupTitle(localizedText("维护工具"))
            }
            item {
                SettingsNavigationGroup(
                    items = listOf(
                        SettingsNavigationItemData(
                        title = localizedText(if (ruleScope == RuleScope.DNS) "清理全部 DNS 规则" else "清理全部 HTTPS 规则"),
                        subtitle = localizedText(if (ruleScope == RuleScope.DNS) "清除当前 DNS 规则后可重新导入，不影响 Go 隧道规则" else "清除当前 HTTPS 规则后可重新导入，不影响传统 DNS 规则"),
                        onClick = { showClearAllRulesDialog = true }
                        )
                    )
                )
            }
        }
    }

    if (showClearAllRulesDialog) {
        ConfirmDialog(
            title = localizedText(if (ruleScope == RuleScope.DNS) "删除全部 DNS 规则" else "删除全部 HTTPS 规则"),
            text = localizedText(if (ruleScope == RuleScope.DNS) "确定要删除全部 DNS 规则吗？手动添加和订阅导入的域名屏蔽、白名单及 IPv4/IPv6 覆写规则都会被移除。Go 隧道规则不受影响。" else "确定要删除全部 HTTPS 规则吗？手动添加和订阅导入的域名、URL、白名单和覆写规则都会被移除。传统 DNS 规则不受影响。"),
            onConfirm = {
                showClearAllRulesDialog = false
                scope.launch(Dispatchers.IO) {
                    clearAllRules(context, ruleScope)
                    withContext(Dispatchers.Main) {
                        viewModel.loadRuleCount()
                        onRuntimeDnsSettingsChanged()
                        Toast.makeText(context, localizedText(context, "已删除当前范围的全部规则"), Toast.LENGTH_SHORT).show()
                    }
                }
            },
            onDismiss = { showClearAllRulesDialog = false }
        )
    }

    if (showAddRuleDialog) {
        AlertDialog(
            onDismissRequest = ::closeAddRuleDialog,
            title = { Text(localizedText("添加屏蔽域名")) },
            text = {
                OutlinedTextField(
                    value = newRule,
                    onValueChange = {
                        newRule = it
                        addRuleError = null
                    },
                    label = { Text(localizedText("要屏蔽的域名，如 example.com")) },
                    supportingText = {
                        Text(localizedText(addRuleError ?: "请输入域名或支持的过滤规则"))
                    },
                    isError = addRuleError != null,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val rule = newRule.trim()
                        if (rule.isBlank()) {
                            addRuleError = "请输入要屏蔽的域名"
                            return@TextButton
                        }
                        viewModel.addRule(rule) { message ->
                            if (message == "已添加到屏蔽规则") {
                                addResult = message
                                newRule = ""
                                closeAddRuleDialog()
                            } else {
                                addRuleError = message
                            }
                        }
                    }
                ) {
                    Text(localizedText("确定"))
                }
            },
            dismissButton = {
                TextButton(onClick = ::closeAddRuleDialog) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

    if (showAddAllowRuleDialog) {
        AlertDialog(
            onDismissRequest = ::closeAddAllowRuleDialog,
            title = { Text(localizedText("添加放行域名")) },
            text = {
                OutlinedTextField(
                    value = newAllowRule,
                    onValueChange = {
                        newAllowRule = it
                        addAllowRuleError = null
                    },
                    label = { Text(localizedText("要放行的域名，如 example.com")) },
                    supportingText = {
                        Text(localizedText(addAllowRuleError ?: "请输入域名或支持的白名单规则"))
                    },
                    isError = addAllowRuleError != null,
                    singleLine = true,
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                    shape = SettingsCornerShape,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val rule = newAllowRule.trim()
                        if (rule.isBlank()) {
                            addAllowRuleError = "请输入要放行的域名"
                            return@TextButton
                        }
                        viewModel.addAllowRule(rule) { message ->
                            if (message == "已添加到白名单规则") {
                                addAllowResult = message
                                newAllowRule = ""
                                closeAddAllowRuleDialog()
                            } else {
                                addAllowRuleError = message
                            }
                        }
                    }
                ) {
                    Text(localizedText("确定"))
                }
            },
            dismissButton = {
                TextButton(onClick = ::closeAddAllowRuleDialog) {
                    Text(localizedText("取消"))
                }
            }
        )
    }

    if (showAddRewriteRuleDialog) {
        AlertDialog(
            onDismissRequest = ::closeAddRewriteRuleDialog,
            title = { Text(localizedText("添加覆写域名")) },
            text = {
                androidx.compose.foundation.layout.Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    androidx.compose.foundation.layout.Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        (if (ruleScope == RuleScope.DNS) listOf(RewriteTargetType.IPV4, RewriteTargetType.IPV6) else listOf(RewriteTargetType.CNAME)).forEach { type ->
                            FilterChip(
                                selected = rewriteTargetType == type,
                                onClick = { rewriteTargetType = type; rewriteAddress = ""; addRewriteRuleError = null },
                                border = BorderStroke(1.dp, MaterialTheme.colorScheme.outline),
                                label = {
                                    androidx.compose.foundation.layout.Box(
                                        modifier = Modifier.fillMaxWidth(),
                                        contentAlignment = androidx.compose.ui.Alignment.Center
                                    ) {
                                        Text(type)
                                    }
                                },
                                modifier = Modifier.weight(1f)
                            )
                        }
                    }
                    OutlinedTextField(value = rewriteDomain, onValueChange = { rewriteDomain = it; addRewriteRuleError = null }, label = { Text(localizedText("域名，如 example.com")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                    OutlinedTextField(
                        value = rewriteAddress,
                        onValueChange = { rewriteAddress = it; addRewriteRuleError = null },
                        label = { Text(localizedText(if (rewriteTargetType == RewriteTargetType.CNAME) "目标域名" else "$rewriteTargetType 地址")) },
                        supportingText = addRewriteRuleError?.let { error -> { Text(localizedText(error)) } },
                        isError = addRewriteRuleError != null,
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = { TextButton(onClick = { viewModel.addRewriteRule(rewriteDomain, rewriteTargetType, rewriteAddress) { message ->
                if (message == "已添加覆写域名") {
                    addResult = message
                    closeAddRewriteRuleDialog()
                } else {
                    addRewriteRuleError = message
                    Toast.makeText(context, localizedText(context, message), Toast.LENGTH_SHORT).show()
                }
            } }) { Text(localizedText("确定")) } },
            dismissButton = { TextButton(onClick = ::closeAddRewriteRuleDialog) { Text(localizedText("取消")) } }
        )
    }

    if (showAddUrlRuleDialog || showAddUrlAllowRuleDialog) {
        val allow = showAddUrlAllowRuleDialog
        AlertDialog(
            onDismissRequest = { showAddUrlRuleDialog = false; showAddUrlAllowRuleDialog = false },
            title = { Text(localizedText(if (allow) "添加放行 URL" else "添加屏蔽 URL")) },
            text = {
                OutlinedTextField(
                    value = newUrlRule,
                    onValueChange = { newUrlRule = it },
                    label = { Text(localizedText("完整 URL，如 https://example.com/js")) },
                    supportingText = { Text(localizedText("按协议、主机和路径前缀匹配，忽略查询参数")) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = { TextButton(onClick = {
                viewModel.addUrlRule(newUrlRule, allow) { message ->
                    if (message == "已添加 URL 规则") { showAddUrlRuleDialog = false; showAddUrlAllowRuleDialog = false; addResult = message }
                    else Toast.makeText(context, localizedText(context, message), Toast.LENGTH_SHORT).show()
                }
            }) { Text(localizedText("确定")) } },
            dismissButton = { TextButton(onClick = { showAddUrlRuleDialog = false; showAddUrlAllowRuleDialog = false }) { Text(localizedText("取消")) } }
        )
    }
}
