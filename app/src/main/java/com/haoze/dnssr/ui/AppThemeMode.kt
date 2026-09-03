package com.haoze.dnssr.ui

enum class AppThemeMode(
    val storageValue: String,
    val displayName: String
) {
    SYSTEM("system", "跟随系统"),
    LIGHT("light", "浅色模式"),
    DARK("dark", "深色模式");

    companion object {
        fun fromStorageValue(value: String?): AppThemeMode =
            entries.firstOrNull { it.storageValue == value } ?: SYSTEM
    }
}
