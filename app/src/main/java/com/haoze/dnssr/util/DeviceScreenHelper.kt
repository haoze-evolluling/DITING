package com.haoze.dnssr.util

import android.content.Context
import android.os.Build
import android.util.DisplayMetrics
import android.view.WindowManager

/**
 * 设备屏幕辅助工具：根据屏幕分辨率判定设备类型。
 *
 * 判定标准与系统 sw600dp 资源限定符一致：取整块物理屏幕宽高中较短的一边，
 * 换算成 dp 后不小于 [TABLET_MIN_SMALLEST_WIDTH_DP] 即视为平板，否则视为手机。
 * 该换算同时使用分辨率与像素密度，可避免大分辨率小屏手机被误判为平板。
 * 使用整屏尺寸而非当前窗口尺寸，因此在分屏、自由窗口等模式下判定结果不受影响。
 */
object DeviceScreenHelper {

    /** 平板判定阈值（dp），与系统 sw600dp 资源限定符一致。 */
    private const val TABLET_MIN_SMALLEST_WIDTH_DP = 600

    /** 判断当前设备是否为平板设备。 */
    fun isTabletDevice(context: Context): Boolean {
        val density = context.resources.displayMetrics.density
        if (density <= 0f) return false
        val (widthPx, heightPx) = getRealDisplaySizePx(context)
        if (widthPx <= 0 || heightPx <= 0) return false
        val smallestWidthDp = minOf(widthPx, heightPx) / density
        return smallestWidthDp >= TABLET_MIN_SMALLEST_WIDTH_DP
    }

    /** 获取整块物理屏幕的宽高像素，取值不随当前旋转方向变化（宽高会互换，调用方取短边即可）。 */
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
