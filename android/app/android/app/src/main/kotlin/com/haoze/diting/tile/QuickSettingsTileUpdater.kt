package com.haoze.diting.tile

import android.content.ComponentName
import android.content.Context
import android.service.quicksettings.TileService
import android.util.Log
import com.haoze.diting.automation.StateBroadcaster
import com.haoze.diting.widget.DitingWidgetProvider

object QuickSettingsTileUpdater {
    private const val TAG = "QuickSettingsTileUpdater"

    const val TILE_SERVICE_CLASS = "com.haoze.diting.tile.DitingTileService"

    fun requestTileUpdate(context: Context) {
        runCatching {
            val appContext = context.applicationContext
            val component = ComponentName(appContext.packageName, TILE_SERVICE_CLASS)
            TileService.requestListeningState(appContext, component)
        }.onFailure { Log.w(TAG, "Failed to request tile listening state", it) }
        DitingWidgetProvider.requestRefresh(context)
        runCatching { StateBroadcaster.broadcast(context) }
            .onFailure { Log.w(TAG, "广播自动化状态失败", it) }
    }
}
