package com.haoze.dnssr.vpn

/**
 * Status of a log item in the floating overlay.
 */
enum class FloatingLogStatus {
    PASSED,
    REWRITTEN,
    BLOCKED,
    BYPASSED,
    ERROR
}

/**
 * Presentation model representing a single log item in the overlay.
 */
data class FloatingLogItem(
    val timestamp: Long,
    val title: String,
    val subtitle: String,
    val detail: String?,
    val status: FloatingLogStatus
)

/**
 * Dimensions (width and height in dp) for the floating log panel.
 */
data class FloatingPanelDimensions(
    val width: Int,
    val height: Int
)

/**
 * Resolved theme color palette for overlay components.
 */
data class OverlayThemePalette(
    val isDark: Boolean,
    val panelBg: Int,
    val panelBorder: Int,
    val headerTitleColor: Int,
    val headerButtonBg: Int,
    val headerButtonTint: Int,
    val dividerColor: Int,
    val cardBg: Int,
    val cardBorder: Int,
    val cardTitleColor: Int,
    val cardSubtitleColor: Int,
    val cardDetailColor: Int,
    val emptyTextColor: Int,
    val passedColor: Int,
    val blockedColor: Int,
    val rewrittenColor: Int,
    val bypassedColor: Int,
    val errorColor: Int
)
