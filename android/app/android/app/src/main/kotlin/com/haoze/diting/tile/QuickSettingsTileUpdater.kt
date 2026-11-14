package com.haoze.diting.tile

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService
import android.util.Log
import com.haoze.diting.automation.StateBroadcaster
import com.haoze.diting.widget.DitingWidgetProvider

/// Asks the system to re-read the tile: `onStartListening` fires, and the tile then paints the
/// service state that just changed. Without it a tile started in the background keeps showing the
/// state it had when the panel last closed. The home screen widget is repainted at the same time so
/// it follows every state change too.
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
        // The widget shows the same state; a no-op when nothing is placed.
        DitingWidgetProvider.requestRefresh(context)
        // 状态一变就广播冻结 JSON 供外部自动化联动；失败不影响磁贴/小组件刷新。
        runCatching { StateBroadcaster.broadcast(context) }
            .onFailure { Log.w(TAG, "广播自动化状态失败", it) }
    }
}
