package com.haoze.diting.tile

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.util.Log
import androidx.core.content.ContextCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.server.DitingDnsServerService

/// Quick settings tile mirroring the legacy one: it toggles whichever data plane the current work
/// mode uses, and falls back to opening the app when it cannot start the service on its own.
///
/// The work mode and the first-run agreement are read from the same preferences the Flutter side
/// writes, so the tile never starts a tunnel before the user accepted the agreement.
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
        // The panel is reachable while locked, but starting a foreground service, opening an
        // activity or showing the VPN consent dialog is refused there; ask for the unlock first.
        if (isLocked) unlockAndRun { performTileAction() } else performTileAction()
    }

    private fun performTileAction() {
        if (!isInitialAgreementAccepted()) {
            // The app owns the consent flow; opening it is the only correct action here.
            openMainActivity(requestStart = true)
            return
        }
        when (workMode()) {
            WORK_MODE_DNS -> toggleServerService()
            WORK_MODE_EXPRESS -> toggleExpressVpn()
            else -> toggleNormalVpn()
        }
    }

    private fun toggleNormalVpn() {
        if (isNormalRunning()) {
            startService(DitingVpnService.stopIntent(this))
            updateTileState(running = false)
            return
        }
        if (VpnService.prepare(this) != null) {
            // Only an activity may show the consent dialog.
            openMainActivity(requestStart = true)
            return
        }
        val start = DitingVpnService.restoreIntent(this)
        if (start == null) {
            // No start config was ever stored: Dart builds it, so let the app start the tunnel.
            openMainActivity(requestStart = true)
            return
        }
        val accepted = startForegroundFromTile(start, "VPN")
        updateTileState(running = accepted)
        if (!accepted) openMainActivity(requestStart = true)
    }

    private fun toggleExpressVpn() {
        if (isExpressRunning()) {
            startService(ExpressVpnService.stopIntent(this))
            updateTileState(running = false)
            return
        }
        if (VpnService.prepare(this) != null) {
            openMainActivity(requestStart = true)
            return
        }
        val start = ExpressVpnService.restoreIntent(this)
        if (start == null) {
            openMainActivity(requestStart = true)
            return
        }
        val accepted = startForegroundFromTile(start, "Express VPN")
        updateTileState(running = accepted)
        if (!accepted) openMainActivity(requestStart = true)
    }

    private fun toggleServerService() {
        if (isServerRunning()) {
            startService(DitingDnsServerService.stopIntent(this))
            updateTileState(running = false)
            return
        }
        val start = DitingDnsServerService.restoreIntent(this)
        if (start == null) {
            openMainActivity(requestStart = true)
            return
        }
        val accepted = startForegroundFromTile(start, "DNS server")
        // The listener binds asynchronously and pushes its real state through
        // `QuickSettingsTileUpdater`; until then only the accepted start is known.
        updateTileState(running = accepted)
        if (!accepted) openMainActivity(requestStart = true)
    }

    private fun startForegroundFromTile(intent: Intent, label: String): Boolean =
        runCatching { ContextCompat.startForegroundService(this, intent) }
            .onFailure { Log.e(TAG, "Failed to start $label from tile", it) }
            .isSuccess

    private fun openMainActivity(requestStart: Boolean) {
        val launch = Runnable {
            val intent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                if (requestStart) putExtra(MainActivity.EXTRA_AUTO_START_VPN, true)
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

    private fun updateTileState(running: Boolean = isCurrentModeRunning()) {
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

    private fun isCurrentModeRunning(): Boolean = when (workMode()) {
        WORK_MODE_DNS -> isServerRunning()
        WORK_MODE_EXPRESS -> isExpressRunning()
        else -> isNormalRunning()
    }

    /// Static flags are authoritative: every service runs in this process, so a stale value cannot
    /// outlive a restart the way a persisted flag would.
    private fun isNormalRunning(): Boolean = DitingVpnService.isRunning

    private fun isExpressRunning(): Boolean = ExpressVpnService.isRunning

    private fun isServerRunning(): Boolean = DitingDnsServerService.isRunning

    /// `normal` / `dns` / `express`; a missing value means the default (normal) mode.
    private fun workMode(): String =
        getSharedPreferences(WORK_MODE_PREFS, Context.MODE_PRIVATE)
            .getString(KEY_WORK_MODE, null)
            ?: WORK_MODE_NORMAL

    private fun isInitialAgreementAccepted(): Boolean =
        getSharedPreferences(UI_PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_INITIAL_AGREEMENT_ACCEPTED, false)

    companion object {
        private const val TAG = "DitingTileService"

        /// Container names shared with the legacy app and the Flutter side.
        private const val UI_PREFS = "dns_vpn_prefs"
        private const val WORK_MODE_PREFS = "diting_settings"

        private const val KEY_INITIAL_AGREEMENT_ACCEPTED = "initial_agreement_accepted"
        private const val KEY_WORK_MODE = "app_work_mode"

        private const val WORK_MODE_NORMAL = "normal"
        private const val WORK_MODE_DNS = "dns"
        private const val WORK_MODE_EXPRESS = "express"
    }
}
