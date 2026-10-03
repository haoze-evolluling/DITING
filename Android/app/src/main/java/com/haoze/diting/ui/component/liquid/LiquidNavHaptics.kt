package com.haoze.diting.ui.component.liquid

import android.os.Build
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import com.haoze.diting.ui.settings.AppearanceSettingsStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Haptic feedback driver for the liquid floating navigation bar.
 * Provides granular tactile feedback for drag gear-stepping, boundary collision,
 * tab switching confirmation, and active tab elastic rebounding.
 */
class LiquidNavHaptics(
    private val view: View,
    var enabled: Boolean
) {
    private val dragTickConstant: Int = if (Build.VERSION.SDK_INT >= 34) {
        // HapticFeedbackConstants.SEGMENT_TICK (API 34)
        27
    } else {
        HapticFeedbackConstants.CLOCK_TICK
    }

    private val boundaryBumpConstant: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        HapticFeedbackConstants.REJECT
    } else {
        HapticFeedbackConstants.CLOCK_TICK
    }

    private val tabSwitchConstant: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        HapticFeedbackConstants.CONFIRM
    } else {
        HapticFeedbackConstants.KEYBOARD_TAP
    }

    /**
     * Triggered when sliding across adjacent tab item boundaries during a drag gesture.
     * Matches FlClash's gear-stepping selection click sensation.
     */
    fun onDragSlideTick() {
        if (!enabled) return
        view.performHapticFeedback(dragTickConstant, HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
    }

    /**
     * Triggered once when reaching the outer overdrag rubber-band boundary limit.
     */
    fun onDragBoundaryBump() {
        if (!enabled) return
        view.performHapticFeedback(boundaryBumpConstant, HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
    }

    /**
     * Triggered on tab switch click, giving a solid mechanical switch confirmation pulse.
     */
    fun onTabSwitchClick() {
        if (!enabled) return
        view.performHapticFeedback(tabSwitchConstant, HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
    }

    /**
     * Triggered when re-tapping the already active tab.
     * Generates an elastic spring double-pulse sensation paired with the jelly rebound animation.
     */
    fun onActiveTabRebound(coroutineScope: CoroutineScope) {
        if (!enabled) return
        view.performHapticFeedback(tabSwitchConstant, HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        coroutineScope.launch(Dispatchers.Main.immediate) {
            delay(40L)
            view.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK, HapticFeedbackConstants.FLAG_IGNORE_VIEW_SETTING)
        }
    }
}

@Composable
fun rememberLiquidNavHaptics(
    enabled: Boolean = AppearanceSettingsStore.isBottomBarHapticEnabled(LocalContext.current)
): LiquidNavHaptics {
    val view = LocalView.current
    return remember(view, enabled) {
        LiquidNavHaptics(view = view, enabled = enabled)
    }
}
