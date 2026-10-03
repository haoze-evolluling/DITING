package com.haoze.diting.ui

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
