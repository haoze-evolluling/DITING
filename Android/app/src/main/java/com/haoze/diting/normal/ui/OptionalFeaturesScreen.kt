package com.haoze.diting.normal.ui

import androidx.compose.runtime.Composable

/**
 * Backward compatibility wrapper for [HiddenFeaturesScreen].
 */
@Composable
fun OptionalFeaturesScreen(
    onBack: () -> Unit
) {
    HiddenFeaturesScreen(onBack = onBack)
}
