package com.haoze.diting.permission

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.haoze.diting.ui.localizedText
import com.haoze.diting.ui.mode.AppWorkMode

/**
 * 嵌入各模式主页顶部的权限与就绪状态感知提醒卡片。
 *
 * 自动感知核心权限（VPN/通知）缺失与保活建议（电池优化）状态。
 * 阻断级不可彻底关闭；建议级支持一键优化与忽略；全部满足时自动平滑收起。
 */
@Composable
fun ModeReadinessBanner(
    mode: AppWorkMode,
    onFixPermission: (AppPermission) -> Unit,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    var readinessState by remember(mode) {
        mutableStateOf(ModeReadinessEvaluator.evaluate(context, mode))
    }
    var refreshTrigger by remember { mutableStateOf(0) }

    DisposableEffect(lifecycleOwner, mode, refreshTrigger) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                AppListPermissionHelper.invalidateCache()
                BatteryOptimizationHelper.invalidateCache()
                readinessState = ModeReadinessEvaluator.evaluate(context, mode)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    val missingRequired = readinessState.missingRequired
    val activeRecommended = readinessState.getActiveRecommended(context)
    val isVisible = missingRequired.isNotEmpty() || activeRecommended.isNotEmpty()

    AnimatedVisibility(
        visible = isVisible,
        enter = expandVertically() + fadeIn(),
        exit = shrinkVertically() + fadeOut(),
        modifier = modifier
    ) {
        if (missingRequired.isNotEmpty()) {
            val primaryMissing = missingRequired.first()
            val bannerTitle = if (missingRequired.size == 1) {
                "${primaryMissing.title}未授予"
            } else {
                "核心运行权限未就绪 (${missingRequired.size} 项)"
            }
            val bannerDesc = when (primaryMissing) {
                AppPermission.VPN -> "当前${mode.title}需要建立本地 VPN 通道接管与解析 DNS，请授权后使用"
                AppPermission.NOTIFICATION -> "需要前台通知权限以维持服务正常运行并显示当前状态"
                else -> primaryMissing.summary
            }

            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp),
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.95f),
                contentColor = MaterialTheme.colorScheme.onErrorContainer,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.error.copy(alpha = 0.35f))
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.WarningAmber,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.error,
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Text(
                            text = localizedText(context, bannerTitle),
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f)
                        )
                    }

                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = localizedText(context, bannerDesc),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer.copy(alpha = 0.85f)
                    )

                    Spacer(modifier = Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        Button(
                            onClick = { onFixPermission(primaryMissing) },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.error,
                                contentColor = MaterialTheme.colorScheme.onError
                            ),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Text(localizedText(context, "立即授权"))
                        }
                    }
                }
            }
        } else if (activeRecommended.isNotEmpty()) {
            val primaryRec = activeRecommended.first()
            val bannerTitle = "后台稳定性建议：${primaryRec.title}"
            val bannerDesc = "建议将谛听加入电池优化白名单，防止息屏后后台解析守护进程被系统强制回收。"

            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 6.dp),
                shape = RoundedCornerShape(16.dp),
                color = MaterialTheme.colorScheme.secondaryContainer.copy(alpha = 0.92f),
                contentColor = MaterialTheme.colorScheme.onSecondaryContainer,
                border = BorderStroke(1.dp, MaterialTheme.colorScheme.secondary.copy(alpha = 0.25f))
            ) {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Info,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.secondary,
                            modifier = Modifier.size(24.dp)
                        )
                        Spacer(modifier = Modifier.width(10.dp))
                        Text(
                            text = localizedText(context, bannerTitle),
                            style = MaterialTheme.typography.titleMedium,
                            color = MaterialTheme.colorScheme.onSecondaryContainer,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(
                            onClick = {
                                ModePermissionStore.setRecommendationDismissed(context, primaryRec, true)
                                refreshTrigger++
                            },
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(
                                imageVector = Icons.Outlined.Close,
                                contentDescription = localizedText(context, "忽略"),
                                tint = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.6f)
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(6.dp))
                    Text(
                        text = localizedText(context, bannerDesc),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSecondaryContainer.copy(alpha = 0.85f)
                    )

                    Spacer(modifier = Modifier.height(12.dp))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End
                    ) {
                        OutlinedButton(
                            onClick = {
                                ModePermissionStore.setRecommendationDismissed(context, primaryRec, true)
                                refreshTrigger++
                            },
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Text(localizedText(context, "不再提示"))
                        }
                        Spacer(modifier = Modifier.width(8.dp))
                        Button(
                            onClick = { onFixPermission(primaryRec) },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.secondary,
                                contentColor = MaterialTheme.colorScheme.onSecondary
                            ),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Text(localizedText(context, "去优化"))
                        }
                    }
                }
            }
        }
    }
}
