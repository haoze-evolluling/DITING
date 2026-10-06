package com.haoze.diting.express.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.haoze.diting.ui.mode.AppWorkMode
import com.haoze.diting.ui.mode.WorkModeCard

/**
 * Environment compatibility checker for Express Mode.
 * Ensures the runtime is at least Android 7+ (API 24) and running on a 64-bit architecture.
 */
object ExpressEnvironmentChecker {
    fun isSupported(): Boolean = AppWorkMode.EXPRESS.isSupportedOnCurrentDevice()
}

/**
 * Dedicated work mode selection card for Express Mode.
 * Delegates to the unified [WorkModeCard].
 */
@Composable
fun ExpressWorkModeCard(
    isSelected: Boolean,
    index: Int = 0,
    itemCount: Int = 1,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    WorkModeCard(
        mode = AppWorkMode.EXPRESS,
        isSelected = isSelected,
        index = index,
        itemCount = itemCount,
        onClick = onClick,
        modifier = modifier
    )
}
