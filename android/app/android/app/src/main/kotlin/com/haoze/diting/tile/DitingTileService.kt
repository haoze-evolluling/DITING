package com.haoze.diting.tile

import android.app.PendingIntent
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.control.DataPlaneControl

class DitingTileService : TileService() {

    override fun onTileAdded() {
        super.onTileAdded()
        updateTileState()
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileState()
    }

    override fun onClick() {
        super.onClick()
        if (isLocked) unlockAndRun { performTileAction() } else performTileAction()
    }

    private fun performTileAction() {
        if (!DataPlaneControl.isAgreementAccepted(this)) {
            openMainActivity()
            return
        }
        when (DataPlaneControl.toggle(this)) {
            DataPlaneControl.Result.Started -> updateTileState(running = true)
            DataPlaneControl.Result.Stopped -> updateTileState(running = false)
            DataPlaneControl.Result.NeedsApp -> openMainActivity()
        }
    }

    private fun openMainActivity() {
        val launch = Runnable {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    val pending = PendingIntent.getActivity(
                        this,
                        0,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                    startActivityAndCollapse(pending)
                } else {
                    @Suppress("DEPRECATION")
                    startActivityAndCollapse(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start MainActivity from tile", e)
            }
        }
        if (isLocked) unlockAndRun(launch) else launch.run()
    }

    private fun updateTileState(running: Boolean = DataPlaneControl.isRunning(this)) {
        val tile = qsTile ?: return
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.quick_settings_tile_label)
        val stateText = getString(
            if (running) R.string.quick_settings_tile_state_on
            else R.string.quick_settings_tile_state_off,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            tile.subtitle = stateText
        }
        tile.contentDescription = "${tile.label} - $stateText"
        tile.icon = Icon.createWithResource(this, R.drawable.dns_svgrepo_com)
        runCatching { tile.updateTile() }
            .onFailure { Log.w(TAG, "Failed to call qsTile.updateTile()", it) }
    }

    companion object {
        private const val TAG = "DitingTileService"
    }
}
