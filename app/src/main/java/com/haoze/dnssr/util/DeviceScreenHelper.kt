package com.haoze.dnssr.util

import android.content.Context
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager

/**
 * Device screen helper: classifies the device type from screen resolution.
 *
 * The criterion matches the system sw600dp resource qualifier: take the
 * shorter side of the full physical screen, convert it to dp, and treat the
 * device as a tablet if the result is at least [TABLET_MIN_SMALLEST_WIDTH_DP],
 * otherwise as a phone. The conversion uses both resolution and pixel density,
 * which prevents high-resolution small-screen phones from being misclassified
 * as tablets. The full screen size is used instead of the current window size,
 * so the classification is unaffected by split-screen or free-form window modes.
 */
object DeviceScreenHelper {

    /** Tablet classification threshold (dp), matching the system sw600dp resource qualifier. */
    private const val TABLET_MIN_SMALLEST_WIDTH_DP = 600

    /** Returns whether the current device is a tablet. */
    fun isTabletDevice(context: Context): Boolean {
        val density = context.resources.displayMetrics.density
        if (density <= 0f) return false
        val (widthPx, heightPx) = getRealDisplaySizePx(context)
        if (widthPx <= 0 || heightPx <= 0) return false
        val smallestWidthDp = minOf(widthPx, heightPx) / density
        return smallestWidthDp >= TABLET_MIN_SMALLEST_WIDTH_DP
    }

    /** Returns the full physical screen size in pixels; the value does not change with the
     *  current rotation (width and height swap, so callers should use the shorter side). */
    private fun getRealDisplaySizePx(context: Context): Pair<Int, Int> {
        val windowManager = context.getSystemService(WindowManager::class.java)
            ?: return Pair(0, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val bounds = windowManager.maximumWindowMetrics.bounds
            Pair(bounds.width(), bounds.height())
        } else {
            @Suppress("DEPRECATION")
            val metrics = DisplayMetrics().also { windowManager.defaultDisplay.getRealMetrics(it) }
            Pair(metrics.widthPixels, metrics.heightPixels)
        }
    }
}
