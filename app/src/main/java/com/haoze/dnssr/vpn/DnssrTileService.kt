package com.haoze.dnssr.vpn

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.dnssr.MainActivity
import com.haoze.dnssr.R
import com.haoze.dnssr.ui.AppSettings
import com.haoze.dnssr.ui.localizedText

/**
 * Quick Settings tile service.
 *
 * Shows the VPN state on the system quick settings tile, handles the
 * start/stop interaction, and coordinates with the main app.
 */
class DnssrTileService : TileService() {

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
        val isRunning = DnsVpnService.isRunning(this)
        if (isRunning) {
            // Running: disconnect
            try {
                startService(DnsVpnService.stopIntent(this))
                updateTileState(running = false)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to stop VPN from tile", e)
            }
            return
        }

        // Not running: check whether the initial agreement has been accepted
        if (!AppSettings.isInitialAgreementAccepted(this)) {
            openMainActivity(requestVpn = true)
            return
        }

        // Check the system VPN preparation state
        val prepareIntent = VpnService.prepare(this)
        if (prepareIntent == null) {
            // The system already granted VPN permission; start in the background
            try {
                ContextCompat.startForegroundService(this, DnsVpnService.startIntent(this))
                updateTileState(running = true)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start VPN from tile", e)
                updateTileState(running = false)
            }
        } else {
            // The system consent dialog is needed; collapse the tile and open
            // MainActivity to guide the user
            openMainActivity(requestVpn = true)
        }
    }

    private fun openMainActivity(requestVpn: Boolean) {
        val launchAction = Runnable {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                if (requestVpn) {
                    putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
                }
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    val pendingIntent = PendingIntent.getActivity(
                        this,
                        0,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    startActivityAndCollapse(pendingIntent)
                } else {
                    @Suppress("DEPRECATION")
                    startActivityAndCollapse(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start MainActivity from tile", e)
            }
        }

        if (isLocked) {
            unlockAndRun(launchAction)
        } else {
            launchAction.run()
        }
    }

    private fun updateTileState(running: Boolean = DnsVpnService.isRunning(this)) {
        val tile = qsTile ?: return
        tile.state = if (running) Tile.STATE_ACTIVE else Tile.STATE_INACTIVE
        tile.label = getString(R.string.quick_settings_tile_label)
        val stateText = localizedText(this, if (running) "已开启" else "已关闭")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            tile.subtitle = stateText
        }
        tile.contentDescription = "${tile.label} - $stateText"
        tile.icon = Icon.createWithResource(this, R.drawable.dns_svgrepo_com)
        runCatching {
            tile.updateTile()
        }.onFailure { e ->
            Log.w(TAG, "Failed to call qsTile.updateTile()", e)
        }
    }

    companion object {
        private const val TAG = "DnssrTileService"

        /**
         * Asks the system to refresh the quick settings tile state.
         */
        fun requestTileUpdate(context: Context) {
            runCatching {
                TileService.requestListeningState(
                    context.applicationContext,
                    ComponentName(context.applicationContext, DnssrTileService::class.java)
                )
            }.onFailure { e ->
                Log.w(TAG, "Failed to request tile listening state", e)
            }
        }
    }
}
