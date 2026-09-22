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
import androidx.lifecycle.viewmodel.compose.viewModel
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

@Composable
fun AddSubscriptionScreen(
    onBack: () -> Unit,
    ruleScope: RuleScope = RuleScope.DNS,
    initialKind: String = SubscriptionKind.DOMAIN,
    onRuntimeDnsSettingsChanged: () -> Unit = {},
    viewModel: SubscriptionViewModel = viewModel()
) {
    NavigationSettledEffect(ruleScope) {
        viewModel.activate(ruleScope)
    }

    val mirrorTemplates by viewModel.mirrorTemplates.collectAsStateWithLifecycle(initialValue = emptyList())
    val subscriptionGroups by viewModel.subscriptionGroups.collectAsStateWithLifecycle(initialValue = emptyList())

    var kind by remember { mutableStateOf(SubscriptionKind.normalize(initialKind)) }
    var url by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var groupId by remember { mutableStateOf<Long?>(null) }
    var newGroupName by remember { mutableStateOf("") }
    var useMirror by remember { mutableStateOf(false) }
    var mirrorTemplate by remember { mutableStateOf("") }
    var mirrorFallback by remember { mutableStateOf(true) }
    var isSubmitting by remember { mutableStateOf(false) }

    val trimmedUrl = url.trim()
    val isUrlValid = trimmedUrl.startsWith("http://", ignoreCase = true) || trimmedUrl.startsWith("https://", ignoreCase = true)
    val isMirrorValid = !useMirror || validMirrorTemplate(mirrorTemplate)
    val canImport = isUrlValid && isMirrorValid && !isSubmitting

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
                    text = localizedText("先选择订阅的规则类型，再填写订阅链接。类型决定该订阅只导入黑白名单规则，还是只导入 hosts 地址覆写规则。"),
                    modifier = Modifier.padding(top = 8.dp)
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

            // 镜像加速
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

            // 导入规则按钮
            item {
                Spacer(modifier = Modifier.height(4.dp))
                SettingsActionButton(
                    onClick = {
                        if (canImport) {
                            isSubmitting = true
                            viewModel.addSubscription(
                                url = trimmedUrl,
                                name = name.trim().takeIf { it.isNotEmpty() },
                                kind = kind,
                                mirrorTemplate = mirrorTemplate.trim().takeIf { useMirror },
                                mirrorFallback = mirrorFallback,
                                groupId = groupId,
                                newGroupName = newGroupName.trim().takeIf { it.isNotEmpty() }
                            )
                            onRuntimeDnsSettingsChanged()
                            onBack()
                        }
                    },
                    enabled = canImport,
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                ) {
                    Text(localizedText("导入规则"))
                }
                Spacer(modifier = Modifier.height(16.dp))
            }
        }
    }
}
