package com.haoze.diting.ui.batch

import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ClearAll
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.FileDownload
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.showToast
import kotlinx.coroutines.launch

@Composable
fun BatchAddRulesScreen(
    target: BatchRuleTarget,
    dataset: RuleDataset = RuleDataset.NORMAL,
    onBack: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    val clipboardManager = LocalClipboardManager.current
    val scope = rememberCoroutineScope()
    val db = remember(dataset) { RuleDatabases.forDataset(context, dataset) }

    var inputText by rememberSaveable { mutableStateOf("") }
    var isParsing by remember { mutableStateOf(false) }
    var validationSummary by remember { mutableStateOf<BatchValidationSummary?>(null) }

    val lineCount = remember(inputText) {
        if (inputText.isEmpty()) 1 else inputText.count { it == '\n' } + 1
    }
    val charCount = inputText.length

    val focusRequester = remember { FocusRequester() }

    SettingsScaffold(
        title = localizedText(target.title),
        onBack = onBack,
        actions = {
            IconButton(
                onClick = {
                    val clipText = clipboardManager.getText()?.text
                    if (!clipText.isNullOrEmpty()) {
                        inputText = if (inputText.isEmpty()) {
                            clipText
                        } else {
                            "$inputText\n$clipText"
                        }
                        context.showToast(localizedText(context, "已粘贴"), Toast.LENGTH_SHORT)
                    } else {
                        context.showToast(localizedText(context, "剪贴板为空"), Toast.LENGTH_SHORT)
                    }
                }
            ) {
                Icon(Icons.Filled.ContentPaste, contentDescription = localizedText("粘贴"))
            }

            IconButton(
                onClick = {
                    if (inputText.isNotEmpty()) {
                        inputText = ""
                        context.showToast(localizedText(context, "已清空"), Toast.LENGTH_SHORT)
                    }
                }
            ) {
                Icon(Icons.Filled.ClearAll, contentDescription = localizedText("清空"))
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
        ) {
            // IDE Editor Container
            val scrollState = rememberScrollState()
            val textStyle = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontSize = 13.sp,
                lineHeight = 22.sp,
                color = MaterialTheme.colorScheme.onSurface,
                platformStyle = PlatformTextStyle(includeFontPadding = false)
            )
            val gutterStyle = TextStyle(
                fontFamily = FontFamily.Monospace,
                fontSize = 13.sp,
                lineHeight = 22.sp,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                textAlign = TextAlign.End,
                platformStyle = PlatformTextStyle(includeFontPadding = false)
            )

            val lineNumbersText = remember(lineCount) {
                (1..lineCount).joinToString("\n")
            }
            val gutterWidth = remember(lineCount) {
                val digits = lineCount.toString().length
                maxOf(36.dp, (digits * 9 + 20).dp)
            }

            Surface(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 8.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp)),
                color = MaterialTheme.colorScheme.surface
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxSize()
                        .height(IntrinsicSize.Min)
                        .verticalScroll(scrollState)
                ) {
                    // Line number gutter
                    Box(
                        modifier = Modifier
                            .width(gutterWidth)
                            .fillMaxHeight()
                            .background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f))
                            .padding(vertical = 12.dp, horizontal = 6.dp)
                    ) {
                        Text(
                            text = lineNumbersText,
                            style = gutterStyle,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }

                    // Divider between line numbers and code
                    Box(
                        modifier = Modifier
                            .width(1.dp)
                            .fillMaxHeight()
                            .background(MaterialTheme.colorScheme.outlineVariant)
                    )

                    // Text Editor Area
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .fillMaxHeight()
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null
                            ) {
                                focusRequester.requestFocus()
                            }
                            .padding(vertical = 12.dp, horizontal = 10.dp)
                    ) {
                        if (inputText.isEmpty()) {
                            Text(
                                text = getPlaceholderForTarget(target, dataset),
                                style = textStyle.copy(
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                                )
                            )
                        }

                        BasicTextField(
                            value = inputText,
                            onValueChange = { inputText = it },
                            textStyle = textStyle,
                            cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                            modifier = Modifier
                                .fillMaxWidth()
                                .focusRequester(focusRequester)
                        )
                    }
                }
            }

            // Bottom control bar
            Surface(
                tonalElevation = 2.dp,
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = localizedText("共 $lineCount 行 | $charCount 字符"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    Button(
                        onClick = {
                            if (inputText.isBlank()) {
                                context.showToast(localizedText(context, "请先输入或粘贴规则"), Toast.LENGTH_SHORT)
                                return@Button
                            }
                            scope.launch {
                                isParsing = true
                                val validator = BatchRuleValidator(db, dataset, target)
                                val summary = validator.validate(inputText)
                                validationSummary = summary
                                isParsing = false
                            }
                        },
                        enabled = !isParsing,
                        shape = RoundedCornerShape(10.dp)
                    ) {
                        if (isParsing) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(16.dp),
                                color = MaterialTheme.colorScheme.onPrimary,
                                strokeWidth = 2.dp
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(localizedText("校验中..."))
                        } else {
                            Icon(
                                Icons.Filled.FileDownload,
                                contentDescription = null,
                                modifier = Modifier.size(18.dp)
                            )
                            Spacer(Modifier.width(6.dp))
                            Text(localizedText("导入"), fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }
    }

    // Validation Result and Confirmation Dialog
    validationSummary?.let { summary ->
        BatchAddResultDialog(
            summary = summary,
            onDismiss = { validationSummary = null },
            onConfirm = {
                scope.launch {
                    val validator = BatchRuleValidator(db, dataset, target)
                    val inserted = validator.commit(context, summary.validItems)
                    onRuntimeDnsSettingsChanged()
                    validationSummary = null
                    context.showToast(localizedText(context, "成功添加 $inserted 条规则"), Toast.LENGTH_SHORT)
                    onBack()
                }
            }
        )
    }
}

private fun getPlaceholderForTarget(target: BatchRuleTarget, dataset: RuleDataset): String = when (target) {
    BatchRuleTarget.BLACKLIST -> if (dataset == RuleDataset.NORMAL) {
        "# 支持每行一条规则，示例：\nexample.com\n*.ads.net\n||tracker.com^\n0.0.0.0 telemetry.io\nhttps://example.com/ad-path\n\n# 支持以 # 或 ! 开头的注释行"
    } else {
        "# 支持每行一条域名规则，示例：\nexample.com\n*.ads.net\n||tracker.com^\n0.0.0.0 telemetry.io\n\n# 支持以 # 或 ! 开头的注释行"
    }
    BatchRuleTarget.WHITELIST -> if (dataset == RuleDataset.NORMAL) {
        "# 支持每行一条放行规则，示例：\nexample.com\n*.safe.org\n@@||trusted.com^\n@@example.net\nhttps://example.com/api\n\n# 支持以 # 或 ! 开头的注释行"
    } else {
        "# 支持每行一条放行规则，示例：\nexample.com\n*.safe.org\n@@||trusted.com^\n@@example.net\n\n# 支持以 # 或 ! 开头的注释行"
    }
    BatchRuleTarget.REWRITE -> {
        "# 支持每行一条覆写规则，示例：\nexample.com 1.2.3.4\n192.168.1.1 router.local\napi.server.com -> 10.0.0.1\nalias.com -> cname.target.com\n||test.com^\$dnsrewrite=1.1.1.1\n\n# 支持以 # 或 ! 开头的注释行"
    }
}
