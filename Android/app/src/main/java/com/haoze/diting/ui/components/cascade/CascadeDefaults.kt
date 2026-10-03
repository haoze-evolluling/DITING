package com.haoze.diting.ui.components.cascade

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

/**
 * 谛听 Cascade 菜单的默认样式参数。
 */
object CascadeDefaults {
    /** 菜单默认宽度 */
    val menuWidth: Dp = 200.dp

    /** 菜单最小宽度 */
    val minWidth: Dp = 196.dp

    /** 投射阴影高度 */
    val shadowElevation: Dp = 4.dp

    /** M3 表面色阶抬升高度 */
    val tonalElevation: Dp = 4.dp

    /** 菜单默认圆角形状，遵循谛听规范的 12.dp 圆角 */
    val shape: Shape
        @Composable get() = RoundedCornerShape(12.dp)
}
