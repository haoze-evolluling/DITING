package com.haoze.diting.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import android.app.Application
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Description
import androidx.compose.material3.OutlinedButton
import androidx.compose.ui.platform.LocalContext
import com.haoze.diting.data.entity.SubscriptionSourceType
import com.haoze.diting.ui.showToast
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.data.entity.SubscriptionKind
import com.haoze.diting.ui.components.SettingsActionButton
import com.haoze.diting.ui.components.SettingsCornerShape
import com.haoze.diting.ui.components.SettingsGroupTitle
import com.haoze.diting.ui.components.SettingsInfoText
import com.haoze.diting.ui.components.SettingsItem
import com.haoze.diting.ui.components.SettingsRadioItem
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsSectionSpacing
import com.haoze.diting.ui.components.SettingsSurfaceGroup
import com.haoze.diting.ui.components.SettingsSwitchItem
import com.haoze.diting.ui.components.SettingsCardMargin

@Composable
fun AddSubscriptionScreen(
    onBack: () -> Unit,
    ruleScope: RuleScope = RuleScope.DNS,
    initialKind: String = SubscriptionKind.DOMAIN,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    dataset: RuleDataset = RuleDataset.NORMAL
) {
    val app = LocalContext.current.applicationContext as Application
    val viewModel: SubscriptionViewModel = viewModel(
        key = "add_subscription_${dataset.name}",
        factory = viewModelFactory { initializer { SubscriptionViewModel(app, dataset) } }
    )
    NavigationSettledEffect(ruleScope) {
        viewModel.activate(ruleScope)
    }

    val mirrorTemplates by viewModel.mirrorTemplates.collectAsStateWithLifecycle(initialValue = emptyList())
    val subscriptionGroups by viewModel.subscriptionGroups.collectAsStateWithLifecycle(initialValue = emptyList())

    val context = LocalContext.current
    var sourceType by remember { mutableStateOf(SubscriptionSourceType.REMOTE) }
    var kind by remember { mutableStateOf(SubscriptionKind.normalize(initialKind)) }
    var url by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var localFileUri by remember { mutableStateOf<Uri?>(null) }
    var localFileName by remember { mutableStateOf("") }
    var groupId by remember { mutableStateOf<Long?>(null) }
    var newGroupName by remember { mutableStateOf("") }
    var useMirror by remember { mutableStateOf(false) }
    var mirrorTemplate by remember { mutableStateOf("") }
    var mirrorFallback by remember { mutableStateOf(true) }
    var isSubmitting by remember { mutableStateOf(false) }

    val filePickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
            val fileName = queryFileName(context, uri) ?: "rules.txt"
            if (!fileName.endsWith(".txt", ignoreCase = true)) {
                context.showToast(localizedText(context, "请选择扩展名为 .txt 的规则文件"))
                return@rememberLauncherForActivityResult
            }
            localFileUri = uri
            localFileName = fileName
            if (name.isBlank()) {
                name = fileName.removeSuffix(".txt").removeSuffix(".TXT")
            }
        }
    }

    val trimmedUrl = url.trim()
    val isUrlValid = trimmedUrl.startsWith("http://", ignoreCase = true) || trimmedUrl.startsWith("https://", ignoreCase = true)
    val isMirrorValid = !useMirror || validMirrorTemplate(mirrorTemplate)
    val canImport = if (sourceType == SubscriptionSourceType.REMOTE) {
        isUrlValid && isMirrorValid && !isSubmitting
    } else {
        localFileUri != null && !isSubmitting
    }

    SettingsScaffold(
        title = localizedText("添加规则订阅"),
        onBack = onBack
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            verticalArrangement = Arrangement.spacedBy(SettingsSectionSpacing)
        ) {
            item {
                SettingsInfoText(
                    text = localizedText("支持通过网络地址或本地 TXT 文件导入规则订阅。类型决定该订阅只导入黑白名单规则，还是只导入 hosts 地址覆写规则。"),
                    modifier = Modifier.padding(top = 8.dp)
                )
            }

            // 导入方式
            item { SettingsGroupTitle(localizedText("导入方式")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            SettingsRadioItem(
                                title = localizedText("订阅地址"),
                                subtitle = localizedText("通过网络链接添加规则订阅"),
                                selected = sourceType == SubscriptionSourceType.REMOTE,
                                onClick = { sourceType = SubscriptionSourceType.REMOTE }
                            )
                        },
                        {
                            SettingsRadioItem(
                                title = localizedText("本地文件"),
                                subtitle = localizedText("选择设备中的 TXT 规则文件导入为订阅"),
                                selected = sourceType == SubscriptionSourceType.LOCAL,
                                onClick = { sourceType = SubscriptionSourceType.LOCAL }
                            )
                        }
                    )
                )
            }

            // 规则类型
            item { SettingsGroupTitle(localizedText("规则类型")) }
            item {
                SettingsSurfaceGroup(
                    content = listOf(
                        {
                            SettingsRadioItem(
                                title = localizedText(SubscriptionKind.displayName(SubscriptionKind.DOMAIN)),
                                subtitle = localizedText("仅导入黑名单与白名单域名规则"),
                                selected = kind == SubscriptionKind.DOMAIN,
                                onClick = { kind = SubscriptionKind.DOMAIN }
                            )
                        },
                        {
                            SettingsRadioItem(
                                title = localizedText(SubscriptionKind.displayName(SubscriptionKind.HOSTS)),
                                subtitle = localizedText("仅导入 hosts 地址与 CNAME 覆写规则"),
                                selected = kind == SubscriptionKind.HOSTS,
                                onClick = { kind = SubscriptionKind.HOSTS }
                            )
                        }
                    )
                )
            }

            if (sourceType == SubscriptionSourceType.REMOTE) {
                // 订阅信息
                item { SettingsGroupTitle(localizedText("订阅信息")) }
                item {
                    SettingsSurfaceGroup(
                        content = listOf(
                            {
                                OutlinedTextField(
                                    value = url,
                                    onValueChange = { url = it },
                                    label = { Text(localizedText("订阅地址")) },
                                    placeholder = { Text("https://example.com/rules.txt") },
                                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                                    minLines = 2,
                                    maxLines = 4,
                                    shape = SettingsCornerShape,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp)
                                )
                            },
                            {
                                OutlinedTextField(
                                    value = name,
                                    onValueChange = { name = it },
                                    label = { Text(localizedText("订阅名称（可选）")) },
                                    placeholder = { Text(localizedText("例如：EasyList China")) },
                                    singleLine = true,
                                    shape = SettingsCornerShape,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp)
                                )
                            }
                        )
                    )
                }
                item {
                    SettingsInfoText(localizedText("支持 AdGuard、hosts 及复合网络规则订阅链接。若留空订阅名称，将自动使用链接作为名称。"))
                }
            } else {
                // 本地文件
                item { SettingsGroupTitle(localizedText("本地文件")) }
                item {
                    SettingsSurfaceGroup(
                        content = listOf(
                            {
                                SettingsItem(
                                    title = if (localFileName.isNotEmpty()) localFileName else localizedText("选择本地 TXT 文件"),
                                    subtitle = if (localFileName.isNotEmpty()) localizedText("点击重新选择文件") else localizedText("点击从存储中选择 .txt 规则文件"),
                                    leadingIcon = Icons.Default.Description,
                                    onClick = { filePickerLauncher.launch(arrayOf("text/plain", "*/*")) }
                                ) {
                                    OutlinedButton(
                                        onClick = { filePickerLauncher.launch(arrayOf("text/plain", "*/*")) },
                                        shape = SettingsCornerShape
                                    ) {
                                        Text(localizedText(if (localFileName.isNotEmpty()) "重新选择" else "选择文件"))
                                    }
                                }
                            },
                            {
                                OutlinedTextField(
                                    value = name,
                                    onValueChange = { name = it },
                                    label = { Text(localizedText("订阅名称（可选）")) },
                                    placeholder = {
                                        Text(
                                            if (localFileName.isNotEmpty()) {
                                                localFileName.removeSuffix(".txt").removeSuffix(".TXT")
                                            } else {
                                                localizedText("例如：自定义本地规则")
                                            }
                                        )
                                    },
                                    singleLine = true,
                                    shape = SettingsCornerShape,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(16.dp)
                                )
                            }
                        )
                    )
                }
                item {
                    SettingsInfoText(localizedText("从本地设备选择 TXT 规则文件导入为订阅。若留空订阅名称，将自动使用文件名。"))
                }
            }

            // 所属分组
            item { SettingsGroupTitle(localizedText("所属分组")) }
            item {
                val groupItems = buildList<@Composable () -> Unit> {
                    add {
                        SettingsRadioItem(
                            title = localizedText("未分组"),
                            selected = groupId == null && newGroupName.isBlank(),
                            onClick = {
                                groupId = null
                                newGroupName = ""
                            }
                        )
                    }
                    subscriptionGroups.forEach { group ->
                        add {
                            SettingsRadioItem(
                                title = group.name,
                                selected = groupId == group.id && newGroupName.isBlank(),
                                onClick = {
                                    groupId = group.id
                                    newGroupName = ""
                                }
                            )
                        }
                    }
                    add {
                        OutlinedTextField(
                            value = newGroupName,
                            onValueChange = { value ->
                                newGroupName = value
                                if (value.isNotBlank()) {
                                    groupId = null
                                }
                            },
                            label = { Text(localizedText("新建分组名称（可选）")) },
                            singleLine = true,
                            shape = SettingsCornerShape,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(16.dp)
                        )
                    }
                }
                SettingsSurfaceGroup(content = groupItems)
            }
            item {
                SettingsInfoText(localizedText("为订阅指定所属分组，便于分类管理和批量操作；也可以在此新建分组或保持未分组。"))
            }

            // 镜像加速（仅在线订阅展示）
            if (sourceType == SubscriptionSourceType.REMOTE) {
                item { SettingsGroupTitle(localizedText("镜像加速")) }
                item {
                    val mirrorItems = buildList<@Composable () -> Unit> {
                        add {
                            SettingsSwitchItem(
                                title = localizedText("使用自定义镜像"),
                                subtitle = localizedText("若订阅源访问较慢或受限，可启用镜像站加速下载规则"),
                                checked = useMirror,
                                onCheckedChange = { useMirror = it }
                            )
                        }
                        if (useMirror) {
                            if (mirrorTemplates.isEmpty()) {
                                add {
                                    SettingsItem(
                                        title = localizedText("选择镜像站模板"),
                                        subtitle = localizedText("暂无模板，请先在域名规则 → 镜像站模板中添加。"),
                                        titleColor = MaterialTheme.colorScheme.error
                                    )
                                }
                            } else {
                                mirrorTemplates.forEach { template ->
                                    add {
                                        SettingsRadioItem(
                                            title = template.name,
                                            subtitle = template.template,
                                            selected = mirrorTemplate == template.template,
                                            onClick = { mirrorTemplate = template.template }
                                        )
                                    }
                                }
                            }
                            mirrorPreview(mirrorTemplate, trimmedUrl)?.let { preview ->
                                add {
                                    SettingsItem(
                                        title = localizedText("请求预览"),
                                        subtitle = preview
                                    )
                                }
                            }
                            add {
                                SettingsSwitchItem(
                                    title = localizedText("失败后回退直连"),
                                    subtitle = localizedText("镜像请求失败时尝试直接连接原始地址"),
                                    checked = mirrorFallback,
                                    onCheckedChange = { mirrorFallback = it }
                                )
                            }
                        }
                    }
                    SettingsSurfaceGroup(content = mirrorItems)
                }
                item {
                    SettingsInfoText(localizedText("若订阅源访问较慢或受限，可启用镜像站加速下载规则；无需加速可直接导入。"))
                }
            }

            // 导入规则按钮
            item {
                Spacer(modifier = Modifier.height(4.dp))
                SettingsActionButton(
                    onClick = {
                        if (canImport) {
                            isSubmitting = true
                            if (sourceType == SubscriptionSourceType.REMOTE) {
                                viewModel.addSubscription(
                                    url = trimmedUrl,
                                    name = name.trim().takeIf { it.isNotEmpty() },
                                    kind = kind,
                                    mirrorTemplate = mirrorTemplate.trim().takeIf { useMirror },
                                    mirrorFallback = mirrorFallback,
                                    groupId = groupId,
                                    newGroupName = newGroupName.trim().takeIf { it.isNotEmpty() }
                                )
                            } else {
                                val effectiveName = name.trim().ifEmpty {
                                    localFileName.removeSuffix(".txt").removeSuffix(".TXT").ifEmpty { "Local Rules" }
                                }
                                viewModel.addLocalSubscription(
                                    uri = localFileUri!!,
                                    name = effectiveName,
                                    kind = kind,
                                    groupId = groupId,
                                    newGroupName = newGroupName.trim().takeIf { it.isNotEmpty() }
                                )
                            }
                            onRuntimeDnsSettingsChanged()
                            onBack()
                        }
                    },
                    enabled = canImport,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = SettingsCardMargin)
                ) {
                    Text(localizedText("导入规则"))
                }
                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}

private fun queryFileName(context: Context, uri: Uri): String? {
    if (uri.scheme == ContentResolver.SCHEME_CONTENT) {
        val cursor = runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        }.getOrNull()
        cursor?.use {
            if (it.moveToFirst()) {
                val idx = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx != -1) {
                    val name = it.getString(idx)
                    if (!name.isNullOrBlank()) return name
                }
            }
        }
    }
    return uri.lastPathSegment?.substringAfterLast('/')?.substringAfterLast(':')
}
