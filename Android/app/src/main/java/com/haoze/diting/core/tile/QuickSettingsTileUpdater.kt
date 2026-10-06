package com.haoze.diting.core.tile

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService
import android.util.Log

/**
 * Dispatches Quick Settings tile refresh requests to the system without
 * coupling backend services to the UI/Tile service class.
 */
object QuickSettingsTileUpdater {
    private const val TAG = "QuickSettingsTileUpdater"

    fun requestTileUpdate(context: Context) {
        runCatching {
            val appContext = context.applicationContext
            TileService.requestListeningState(
                appContext,
                ComponentName(appContext.packageName, "${appContext.packageName}.tile.DitingTileService")
            )
        }.onFailure { e ->
            Log.w(TAG, "Failed to request tile listening state", e)
        }
    }
}
