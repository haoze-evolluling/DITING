package com.haoze.dnssr.ui

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import com.haoze.dnssr.ui.localization.LocalizationEngine

/**
 * Composable entry point for string localization.
 * Returns the English translation when the active UI language is English, otherwise returns the original text.
 */
@Composable
fun localizedText(text: String): String {
    val configuration = LocalConfiguration.current
    val context = LocalContext.current
    return if (configuration.locales[0].language == "en") {
        LocalizationEngine.translate(text, context)
    } else {
        text
    }
}

/**
 * Context-aware entry point for string localization.
 * Wraps the context using [AppLanguageManager] and returns the English translation when applicable.
 */
fun localizedText(context: Context, text: String): String {
    val localizedContext = AppLanguageManager.wrap(context)
    return if (localizedContext.resources.configuration.locales[0].language == "en") {
        LocalizationEngine.translate(text, localizedContext)
    } else {
        text
    }
}
