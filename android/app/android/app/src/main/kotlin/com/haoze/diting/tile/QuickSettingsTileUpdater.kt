package com.haoze.diting.tile

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService
import android.util.Log

/// Asks the system to re-read the tile: `onStartListening` fires, and the tile then paints the
/// service state that just changed. Without it a tile started in the background keeps showing the
/// state it had when the panel last closed.
object QuickSettingsTileUpdater {
    private const val TAG = "QuickSettingsTileUpdater"

    /// Fully qualified, because `requestListeningState` matches this exact name; a doubly prefixed
    /// value (`com.haoze.diting.com.haoze.diting...`) never matches and fails silently.
    const val TILE_SERVICE_CLASS = "com.haoze.diting.tile.DitingTileService"

    fun requestTileUpdate(context: Context) {
        runCatching {
            val appContext = context.applicationContext
            val component = ComponentName(appContext.packageName, TILE_SERVICE_CLASS)
            TileService.requestListeningState(appContext, component)
        }.onFailure { Log.w(TAG, "Failed to request tile listening state", it) }
    }
}
