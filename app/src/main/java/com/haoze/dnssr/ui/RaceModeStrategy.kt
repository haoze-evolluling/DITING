package com.haoze.dnssr.ui

enum class RaceModeStrategy(
    val storageValue: String,
    val displayName: String
) {
    BRUTE_FORCE_PARALLEL("brute_force_parallel", "最快响应"),
    SMART_PREDICTION("smart_prediction", "智能选择"),
    PRIMARY_BACKUP("primary_backup", "依次尝试");

    companion object {
        fun fromStorageValue(value: String?): RaceModeStrategy {
            return when (value) {
                "parallel_race", "race", "brute_force_parallel" -> BRUTE_FORCE_PARALLEL
                "smart_prediction", "prediction" -> SMART_PREDICTION
                "primary_backup" -> PRIMARY_BACKUP
                else -> values().firstOrNull { it.storageValue == value } ?: SMART_PREDICTION
            }
        }
    }
}
