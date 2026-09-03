package com.haoze.dnssr.ui

import android.net.Uri
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.data.entity.MirrorTemplateEntity
import com.haoze.dnssr.data.entity.SubscriptionGroupEntity
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsDivider
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsRadioItem
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.ui.components.SettingsSwitchItem

@Composable
internal fun SubscriptionDialogCard(
    title: String,
    content: @Composable ColumnScope.() -> Unit
) {
    SettingsSurfaceGroup(
        groupContentPadding = PaddingValues(0.dp),
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        content = listOf {
            Column(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = localizedText(title),
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
                )
                SettingsDivider()
                Column(content = content)
            }
        }
    )
}

@Composable
internal fun SubscriptionDialogExpandableCard(
    title: String,
    summary: String,
    expanded: Boolean,
    onExpandedChange: (Boolean) -> Unit,
    content: @Composable ColumnScope.() -> Unit
) {
    SettingsSurfaceGroup(
        groupContentPadding = PaddingValues(0.dp),
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        content = listOf {
            Column(modifier = Modifier.fillMaxWidth()) {
                SettingsItem(
                    title = title,
                    subtitle = summary,
                    onClick = { onExpandedChange(!expanded) }
                ) {
                    Icon(
                        imageVector = if (expanded) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown,
                        contentDescription = localizedText(if (expanded) "收起$title" else "展开$title"),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                if (expanded) {
                    SettingsDivider()
                    Column(content = content)
                }
            }
        }
    )
}

@Composable
internal fun SubscriptionUrlField(
    url: String,
    onUrlChange: (String) -> Unit,
    placeholder: String? = null
) {
    OutlinedTextField(
        value = url,
        onValueChange = onUrlChange,
        label = { Text(localizedText("订阅地址")) },
        placeholder = placeholder?.let { value -> { Text(localizedText(value)) } },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
        minLines = 2,
        maxLines = 4,
        shape = SettingsCornerShape,
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
    )
}

@Composable
internal fun SubscriptionNameField(
    name: String,
    onNameChange: (String) -> Unit,
    optional: Boolean = false
) {
    OutlinedTextField(
        value = name,
        onValueChange = onNameChange,
        label = { Text(localizedText(if (optional) "订阅名称（可选）" else "订阅名称")) },
        placeholder = if (optional) { { Text(localizedText("例如：EasyList China")) } } else null,
        singleLine = true,
        shape = SettingsCornerShape,
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
    )
}

@Composable
internal fun selectedGroupSummary(
    groups: List<SubscriptionGroupEntity>,
    selectedGroupId: Long?,
    newGroupName: String
): String = newGroupName.trim().takeIf { it.isNotEmpty() }
    ?: groups.firstOrNull { it.id == selectedGroupId }?.name
    ?: localizedText("未分组")

@Composable
internal fun mirrorSummary(
    mirrorTemplates: List<MirrorTemplateEntity>,
    enabled: Boolean,
    template: String
): String {
    if (!enabled) return localizedText("未使用")
    return mirrorTemplates.firstOrNull { it.template == template }?.name
        ?: if (template.isBlank()) localizedText("未选择模板") else localizedText("自定义镜像")
}

@Composable
internal fun SubscriptionGroupSelector(
    groups: List<SubscriptionGroupEntity>,
    selectedGroupId: Long?,
    newGroupName: String,
    onGroupSelected: (Long?) -> Unit,
    onNewGroupNameChange: (String) -> Unit
) {
    SettingsSurfaceGroup(
        groupContentPadding = PaddingValues.Zero,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        content = buildList {
            add {
                SettingsRadioItem(localizedText("未分组"), selectedGroupId == null && newGroupName.isBlank(), { onGroupSelected(null); onNewGroupNameChange("") })
            }
            groups.forEach { group ->
                add {
                    SettingsRadioItem(group.name, selectedGroupId == group.id && newGroupName.isBlank(), {
                        onGroupSelected(group.id); onNewGroupNameChange("")
                    })
                }
            }
        }
    )
    OutlinedTextField(
        value = newGroupName,
        onValueChange = { value -> onNewGroupNameChange(value); if (value.isNotBlank()) onGroupSelected(null) },
        label = { Text(localizedText("新建分组名称（可选）")) },
        singleLine = true,
        shape = SettingsCornerShape,
        modifier = Modifier
            .fillMaxWidth()
            .padding(16.dp)
    )
}

@Composable
internal fun MirrorEditor(
    originalUrl: String,
    mirrorTemplates: List<MirrorTemplateEntity>,
    enabled: Boolean,
    template: String,
    fallback: Boolean,
    onEnabledChange: (Boolean) -> Unit,
    onTemplateChange: (String) -> Unit,
    onFallbackChange: (Boolean) -> Unit
) {
    SettingsSurfaceGroup(
        groupContentPadding = PaddingValues.Zero,
        containerColor = MaterialTheme.colorScheme.surfaceVariant,
        content = buildList {
            add {
                SettingsSwitchItem(
                    title = localizedText("使用自定义镜像"),
                    checked = enabled,
                    onCheckedChange = onEnabledChange
                )
            }
            if (enabled) {
                if (mirrorTemplates.isEmpty()) {
                    add {
                        SettingsItem(
                            title = localizedText("选择镜像站模板"),
                            subtitle = localizedText("暂无模板，请先在域名规则 → 镜像站模板中添加。"),
                            titleColor = MaterialTheme.colorScheme.error
                        )
                    }
                } else {
                    mirrorTemplates.forEach { item ->
                        add {
                            SubscriptionRadioItem(
                                title = item.name,
                                selected = template == item.template,
                                onClick = { onTemplateChange(item.template) }
                            )
                        }
                    }
                }
                mirrorPreview(template, originalUrl)?.let { preview ->
                    add { SettingsItem(title = localizedText("请求预览"), subtitle = preview) }
                }
                add {
                    SettingsSwitchItem(
                        title = localizedText("失败后回退直连"),
                        checked = fallback,
                        onCheckedChange = onFallbackChange
                    )
                }
            }
        }
    )
}

@Composable
internal fun SubscriptionRadioItem(
    title: String,
    selected: Boolean,
    onClick: () -> Unit,
    subtitle: String? = null
) {
    SettingsRadioItem(
        title = title,
        subtitle = subtitle,
        selected = selected,
        onClick = onClick
    )
}

internal fun validMirrorTemplate(template: String): Boolean {
    val trimmed = template.trim()
    return (trimmed.startsWith("https://") || trimmed.startsWith("http://")) &&
        listOf("{url}", "{urlEncoded}", "{scheme}", "{host}", "{path}", "{pathAndQuery}").any { it in trimmed }
}

internal fun mirrorPreview(template: String, originalUrl: String): String? {
    if (!validMirrorTemplate(template) || originalUrl.isBlank()) return null
    val uri = runCatching { Uri.parse(originalUrl.trim()) }.getOrNull() ?: return null
    val path = uri.encodedPath?.takeIf { it.isNotEmpty() } ?: "/"
    val pathAndQuery = path + (uri.encodedQuery?.let { "?$it" } ?: "")
    return template.trim()
        .replace("{urlEncoded}", Uri.encode(originalUrl.trim()))
        .replace("{url}", originalUrl.trim())
        .replace("{scheme}", uri.scheme.orEmpty())
        .replace("{host}", uri.host.orEmpty())
        .replace("{pathAndQuery}", pathAndQuery)
        .replace("{path}", path)
}
