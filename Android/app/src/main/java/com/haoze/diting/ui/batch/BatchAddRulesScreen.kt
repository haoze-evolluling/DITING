package com.haoze.diting.ui.batch

import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.material3.FilterChip
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalClipboard
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.diting.data.RuleDataset
import com.haoze.diting.data.RuleDatabases
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.components.SettingsCardMargin
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.showToast
import kotlinx.coroutines.launch

@Composable
fun BatchAddRulesScreen(
    target: BatchRuleTarget = BatchRuleTarget.BLACKLIST,
    initialMode: BatchRecognitionMode? = null,
    dataset: RuleDataset = RuleDataset.NORMAL,
    onBack: () -> Unit,
    onRuntimeDnsSettingsChanged: () -> Unit = {}
) {
    val context = LocalContext.current
    val clipboard = LocalClipboard.current
    val scope = rememberCoroutineScope()
    val db = remember(dataset) { RuleDatabases.forDataset(context, dataset) }

    var selectedMode by rememberSaveable {
        mutableStateOf(initialMode ?: BatchRecognitionMode.fromTarget(target))
    }
    var inputText by rememberSaveable { mutableStateOf("") }
    var isParsing by remember { mutableStateOf(false) }
    var validationSummary by remember { mutableStateOf<BatchValidationSummary?>(null) }

    val lineCount = remember(inputText) {
        if (inputText.isEmpty()) 1 else inputText.count { it == '\n' } + 1
    }
    val charCount = inputText.length

    val focusRequester = remember { FocusRequester() }

    SettingsScaffold(
        title = localizedText("规则导入"),
        onBack = onBack,
        actions = {
            IconButton(
                onClick = {
                    scope.launch {
                        val clipEntry = clipboard.getClipEntry()
                        val clipData = clipEntry?.clipData
                        val clipText = if (clipData != null && clipData.itemCount > 0) {
                            clipData.getItemAt(0)?.coerceToText(context)?.toString()
                        } else null
                        if (!clipText.isNullOrEmpty()) {
                            val normalized = clipText.replace("\r\n", "\n").replace('\r', '\n')
                            inputText = if (inputText.isEmpty()) {
                                normalized
                            } else {
                                "$inputText\n$normalized"
                            }
                            context.showToast(localizedText(context, "已粘贴"), Toast.LENGTH_SHORT)
                        } else {
                            context.showToast(localizedText(context, "剪贴板为空"), Toast.LENGTH_SHORT)
                        }
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
            // Mode Selector Bar
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = SettingsCardMargin, vertical = 6.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BatchRecognitionMode.entries.forEach { mode ->
                    val selected = selectedMode == mode
                    FilterChip(
                        selected = selected,
                        onClick = { selectedMode = mode },
                        label = {
                            Text(
                                text = localizedText(mode.title),
                                style = MaterialTheme.typography.labelMedium
                            )
                        },
                        shape = RoundedCornerShape(8.dp)
                    )
                }
            }

            Text(
                text = localizedText(selectedMode.description),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 2.dp)
            )

            // IDE Editor Container
            val scrollState = rememberScrollState()
            val density = LocalDensity.current
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
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.55f),
                platformStyle = PlatformTextStyle(includeFontPadding = false)
            )

            var textLayoutResult by remember { mutableStateOf<TextLayoutResult?>(null) }
            val textMeasurer = rememberTextMeasurer()
            val singleDigitLayout = remember(gutterStyle, textMeasurer) {
                textMeasurer.measure("0", gutterStyle)
            }
            val digitWidth = singleDigitLayout.size.width
            val digitBaseline = singleDigitLayout.firstBaseline

            val digits = remember(lineCount) {
                maxOf(2, lineCount.toString().length)
            }
            val gutterWidth = remember(digits, digitWidth, density) {
                val charWidthDp = with(density) { digitWidth.toDp() }
                maxOf(36.dp, charWidthDp * digits + 18.dp)
            }

            Surface(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth()
                    .padding(start = SettingsCardMargin, end = SettingsCardMargin, top = 6.dp, bottom = 8.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(12.dp)),
                color = MaterialTheme.colorScheme.surface
            ) {
                CodeEditorLayout(
                    modifier = Modifier
                        .fillMaxSize()
                        .verticalScroll(scrollState),
                    gutterWidth = gutterWidth,
                    gutter = {
                        val gutterBg = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)
                        val topPaddingPx = with(density) { 12.dp.toPx() }
                        val rightPaddingPx = with(density) { 8.dp.toPx() }

                        Canvas(
                            modifier = Modifier
                                .fillMaxSize()
                                .clickable(
                                    interactionSource = remember { MutableInteractionSource() },
                                    indication = null
                                ) {
                                    focusRequester.requestFocus()
                                }
                        ) {
                            drawRect(color = gutterBg)

                            val layout = textLayoutResult
                            if (layout == null || inputText.isEmpty()) {
                                val y = topPaddingPx
                                val x = size.width - rightPaddingPx - digitWidth
                                drawText(
                                    textMeasurer = textMeasurer,
                                    text = "1",
                                    topLeft = Offset(x, y),
                                    style = gutterStyle
                                )
                                return@Canvas
                            }

                            val scrollY = scrollState.value
                            val viewportHeight = scrollState.viewportSize
                            val visibleTop = scrollY.toFloat() - 100f
                            val visibleBottom = (scrollY + viewportHeight).toFloat() + 100f
                            val shouldCull = viewportHeight > 0

                            var currentLogicalLine = 1
                            val totalVisualLines = layout.lineCount

                            for (lineIndex in 0 until totalVisualLines) {
                                val lineStartOffset = layout.getLineStart(lineIndex)
                                val isNewLogicalLine = lineIndex == 0 ||
                                        (lineStartOffset > 0 && inputText[lineStartOffset - 1] == '\n')

                                if (isNewLogicalLine) {
                                    val ruleNum = currentLogicalLine++
                                    val lineTop = topPaddingPx + layout.getLineTop(lineIndex)
                                    val lineBottom = topPaddingPx + layout.getLineBottom(lineIndex)

                                    if (shouldCull) {
                                        if (lineBottom < visibleTop) continue
                                        if (lineTop > visibleBottom) break
                                    }

                                    val lineBaseline = topPaddingPx + layout.getLineBaseline(lineIndex)
                                    val numStr = ruleNum.toString()
                                    val numWidth = numStr.length * digitWidth
                                    val x = size.width - rightPaddingPx - numWidth
                                    val y = lineBaseline - digitBaseline

                                    drawText(
                                        textMeasurer = textMeasurer,
                                        text = numStr,
                                        topLeft = Offset(x, y),
                                        style = gutterStyle
                                    )
                                }
                            }
                        }
                    },
                    divider = {
                        Box(
                            modifier = Modifier
                                .fillMaxSize()
                                .background(MaterialTheme.colorScheme.outlineVariant)
                        )
                    },
                    editor = {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
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
                                    text = getUnifiedPlaceholder(dataset),
                                    style = textStyle.copy(
                                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                                    )
                                )
                            }

                            BasicTextField(
                                value = inputText,
                                onValueChange = { inputText = it },
                                onTextLayout = { textLayoutResult = it },
                                textStyle = textStyle,
                                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .focusRequester(focusRequester)
                            )
                        }
                    }
                )
            }

            // Bottom control bar
            Surface(
                tonalElevation = 2.dp,
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = SettingsCardMargin, vertical = 10.dp),
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
                                val summary = validator.validate(inputText, selectedMode)
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
                    val result = validator.commitDetailed(context, summary.validItems)
                    onRuntimeDnsSettingsChanged()
                    validationSummary = null

                    val msg = if (result.totalInserted > 0) {
                        val parts = buildList {
                            if (result.blockInserted > 0) add("黑名单 ${result.blockInserted}")
                            if (result.allowInserted > 0) add("白名单 ${result.allowInserted}")
                            if (result.rewriteInserted > 0) add("覆写 ${result.rewriteInserted}")
                        }.joinToString("，")
                        "成功导入 ${result.totalInserted} 条规则 ($parts)"
                    } else {
                        "未导入任何规则"
                    }
                    context.showToast(localizedText(context, msg), Toast.LENGTH_SHORT)
                    onBack()
                }
            }
        )
    }
}

private fun getUnifiedPlaceholder(dataset: RuleDataset): String = if (dataset == RuleDataset.NORMAL) {
    "# 支持混合粘贴多种规则，系统将自动识别类型：\n# 1. 黑名单：||ad.com^ 或 0.0.0.0 tracker.com 或 bad.com 或 https://example.com/ad\n# 2. 白名单：@@||trusted.com^ 或 @@safe.org 或 @@https://example.com/api\n# 3. 覆写规则：example.com 1.2.3.4 或 api.com -> 10.0.0.1 或 alias.com -> cname.com\n# 4. 支持以 # 或 ! 开头的注释行"
} else {
    "# 支持混合粘贴多种规则（服务器模式）：\n# 1. 黑名单：||ad.com^ 或 0.0.0.0 tracker.com 或 bad.com\n# 2. 白名单：@@||trusted.com^ 或 @@safe.org\n# 3. 覆写规则：example.com 1.2.3.4 或 api.com -> 10.0.0.1 或 alias.com -> cname.com\n# 4. 支持以 # 或 ! 开头的注释行"
}

@Composable
private fun CodeEditorLayout(
    modifier: Modifier = Modifier,
    gutterWidth: Dp,
    gutter: @Composable () -> Unit,
    divider: @Composable () -> Unit,
    editor: @Composable () -> Unit
) {
    Layout(
        content = {
            gutter()
            divider()
            editor()
        },
        modifier = modifier
    ) { measurables, constraints ->
        val gutterWidthPx = gutterWidth.roundToPx()
        val dividerWidthPx = 1.dp.roundToPx()
        val editorWidthPx = (constraints.maxWidth - gutterWidthPx - dividerWidthPx).coerceAtLeast(0)

        val editorPlaceable = measurables[2].measure(
            constraints.copy(
                minWidth = editorWidthPx,
                maxWidth = editorWidthPx,
                minHeight = constraints.minHeight,
                maxHeight = Constraints.Infinity
            )
        )

        val totalHeight = maxOf(constraints.minHeight, editorPlaceable.height)

        val gutterPlaceable = measurables[0].measure(
            Constraints.fixed(gutterWidthPx, totalHeight)
        )

        val dividerPlaceable = measurables[1].measure(
            Constraints.fixed(dividerWidthPx, totalHeight)
        )

        layout(constraints.maxWidth, totalHeight) {
            gutterPlaceable.placeRelative(0, 0)
            dividerPlaceable.placeRelative(gutterWidthPx, 0)
            editorPlaceable.placeRelative(gutterWidthPx + dividerWidthPx, 0)
        }
    }
}
