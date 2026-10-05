package com.haoze.diting.ui.mode

import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import com.haoze.diting.express.ui.ExpressWorkModeCard
import com.haoze.diting.ui.components.AppConfirmDialog
import com.haoze.diting.ui.components.SettingsCardMargin
import com.haoze.diting.ui.components.SettingsItemSpacing
import com.haoze.diting.ui.components.SettingsScaffold
import com.haoze.diting.ui.localizedText
import kotlinx.coroutines.launch

private const val TRANSITION_DURATION_MS = 380

@Composable
fun WorkModeSelectionScreen(
    isFirstLaunch: Boolean,
    currentMode: AppWorkMode = AppWorkMode.NORMAL,
    onBack: () -> Unit = {},
    onModeSelected: (AppWorkMode) -> Unit
) {
    var transitioningMode by remember { mutableStateOf<AppWorkMode?>(null) }
    val transitionAnim = remember { Animatable(0f) }
    val coroutineScope = rememberCoroutineScope()
    var rootCoordinates by remember { mutableStateOf<LayoutCoordinates?>(null) }
    var rootSize by remember { mutableStateOf(IntSize.Zero) }
    val cardBounds = remember { mutableStateMapOf<AppWorkMode, WorkModeTransitionBounds>() }

    BackHandler(enabled = transitioningMode != null) {
        // Prevent back navigation while the transition animation is active
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .onGloballyPositioned { coords ->
                rootCoordinates = coords
                rootSize = coords.size
            }
    ) {
        val baseContentAlpha = if (transitioningMode != null) {
            (1f - transitionAnim.value * 2.5f).coerceIn(0f, 1f)
        } else {
            1f
        }

        Box(
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = baseContentAlpha }
        ) {
            if (isFirstLaunch) {
                Scaffold(
                    modifier = Modifier.fillMaxSize(),
                    containerColor = Color.Transparent
                ) { innerPadding ->
                    WorkModeSelectionContent(
                        isFirstLaunch = true,
                        currentMode = currentMode,
                        transitioningMode = transitioningMode,
                        onCardPositioned = { mode, bounds ->
                            cardBounds[mode] = bounds
                        },
                        rootCoordinates = rootCoordinates,
                        onTriggerTransition = { mode ->
                            if (transitioningMode == null) {
                                transitioningMode = mode
                                coroutineScope.launch {
                                    transitionAnim.animateTo(
                                        targetValue = 1f,
                                        animationSpec = tween(
                                            durationMillis = TRANSITION_DURATION_MS,
                                            easing = FastOutSlowInEasing
                                        )
                                    )
                                    onModeSelected(mode)
                                }
                            }
                        },
                        modifier = Modifier
                            .padding(innerPadding)
                            .statusBarsPadding()
                    )
                }
            } else {
                SettingsScaffold(
                    title = "模式切换",
                    onBack = onBack
                ) { innerPadding ->
                    WorkModeSelectionContent(
                        isFirstLaunch = false,
                        currentMode = currentMode,
                        transitioningMode = transitioningMode,
                        onCardPositioned = { mode, bounds ->
                            cardBounds[mode] = bounds
                        },
                        rootCoordinates = rootCoordinates,
                        onTriggerTransition = { mode ->
                            if (transitioningMode == null) {
                                transitioningMode = mode
                                coroutineScope.launch {
                                    transitionAnim.animateTo(
                                        targetValue = 1f,
                                        animationSpec = tween(
                                            durationMillis = TRANSITION_DURATION_MS,
                                            easing = FastOutSlowInEasing
                                        )
                                    )
                                    onModeSelected(mode)
                                }
                            }
                        },
                        modifier = Modifier.padding(innerPadding)
                    )
                }
            }
        }

        if (transitioningMode != null && rootSize.width > 0 && rootSize.height > 0) {
            val targetMode = transitioningMode!!
            val fallbackBounds = WorkModeTransitionBounds(
                bounds = Rect(
                    left = rootSize.width * 0.08f,
                    top = rootSize.height * 0.35f,
                    right = rootSize.width * 0.92f,
                    bottom = rootSize.height * 0.45f
                ),
                topRadius = 16.dp,
                bottomRadius = 16.dp
            )
            val startBounds = cardBounds[targetMode] ?: fallbackBounds

            WorkModeExpansionOverlay(
                mode = targetMode,
                startBounds = startBounds,
                containerSize = rootSize,
                progress = transitionAnim.value
            )
        }
    }
}

@Composable
private fun WorkModeSelectionContent(
    isFirstLaunch: Boolean,
    currentMode: AppWorkMode,
    transitioningMode: AppWorkMode?,
    onCardPositioned: (AppWorkMode, WorkModeTransitionBounds) -> Unit,
    rootCoordinates: LayoutCoordinates?,
    onTriggerTransition: (AppWorkMode) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val alreadyInModeText = localizedText("当前已处于该模式")
    var pendingSwitchMode by remember { mutableStateOf<AppWorkMode?>(null) }

    if (pendingSwitchMode != null) {
        val targetMode = pendingSwitchMode!!
        AppConfirmDialog(
            onDismissRequest = { pendingSwitchMode = null },
            title = localizedText("确认切换运行模式"),
            message = localizedText("切换模式将重启网络服务并进入对应主界面，您的规则与配置均安全保留。确认切换吗？"),
            confirmLabel = localizedText("确认切换"),
            cancelLabel = localizedText("取消"),
            onConfirm = {
                pendingSwitchMode = null
                onTriggerTransition(targetMode)
            }
        )
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .navigationBarsPadding(),
        contentAlignment = Alignment.Center
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SettingsCardMargin, vertical = if (isFirstLaunch) 32.dp else 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Column(
                modifier = Modifier.widthIn(max = 560.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                WorkModeHeader()

                Spacer(modifier = Modifier.height(28.dp))

                Column(
                    modifier = Modifier.fillMaxWidth(),
                    verticalArrangement = Arrangement.spacedBy(SettingsItemSpacing)
                ) {
                    val modes = AppWorkMode.entries
                    modes.forEachIndexed { index, mode ->
                        val isSelected = !isFirstLaunch && mode == currentMode
                        val topRadius = if (index == 0) 28.dp else 4.dp
                        val bottomRadius = if (index == modes.size - 1) 28.dp else 4.dp
                        val isTransitioning = transitioningMode != null

                        val cardPositionModifier = Modifier.onGloballyPositioned { coords ->
                            val root = rootCoordinates
                            if (coords.isAttached && root != null && root.isAttached) {
                                val rect = root.localBoundingBoxOf(coords)
                                onCardPositioned(
                                    mode,
                                    WorkModeTransitionBounds(
                                        bounds = rect,
                                        topRadius = topRadius,
                                        bottomRadius = bottomRadius
                                    )
                                )
                            }
                        }

                        if (mode == AppWorkMode.EXPRESS) {
                            ExpressWorkModeCard(
                                isSelected = isSelected,
                                index = index,
                                itemCount = modes.size,
                                onClick = {
                                    if (isTransitioning) return@ExpressWorkModeCard
                                    if (isFirstLaunch) {
                                        onTriggerTransition(mode)
                                    } else if (isSelected) {
                                        Toast.makeText(context, alreadyInModeText, Toast.LENGTH_SHORT).show()
                                    } else {
                                        pendingSwitchMode = mode
                                    }
                                },
                                modifier = cardPositionModifier
                            )
                        } else {
                            val isSupported = mode.isSupportedOnCurrentDevice()
                            WorkModeCard(
                                mode = mode,
                                isSelected = isSelected,
                                index = index,
                                itemCount = modes.size,
                                onClick = {
                                    if (isTransitioning) return@WorkModeCard
                                    if (!isSupported) {
                                        Toast.makeText(
                                            context,
                                            localizedText(context, "${mode.title}仅支持 Android 10 (API 29) 及以上系统"),
                                            Toast.LENGTH_SHORT
                                        ).show()
                                    } else if (isFirstLaunch) {
                                        onTriggerTransition(mode)
                                    } else if (isSelected) {
                                        Toast.makeText(context, alreadyInModeText, Toast.LENGTH_SHORT).show()
                                    } else {
                                        pendingSwitchMode = mode
                                    }
                                },
                                modifier = cardPositionModifier.then(
                                    if (!isSupported) Modifier.alpha(0.45f) else Modifier
                                )
                            )
                        }
                    }
                }

                Spacer(modifier = Modifier.height(24.dp))
            }
        }
    }
}
