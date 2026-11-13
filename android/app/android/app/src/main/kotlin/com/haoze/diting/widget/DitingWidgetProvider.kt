package com.haoze.diting.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.control.DataPlaneControl

/// Home screen widget: protection state, today's blocked count and a one-tap toggle.
///
/// Modelled on BlockAds' `AdBlockWidgetProvider`: an unexported receiver for the toggle (so no
/// other app can flip the tunnel through a broadcast) and the database read moved off the main
/// thread with `goAsync`. Three layouts share one provider — the size class is resolved from the
/// widget options on every render, so a resize repaints into the right density instead of
/// stretching one layout.
class DitingWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        renderAll(context, appWidgetManager, appWidgetIds)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        renderAll(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    /// Repaints every placed widget. Called from `QuickSettingsTileUpdater` on each service state
    /// change, so the widget follows starts and stops it did not perform itself.
    private fun renderAll(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        if (appWidgetIds.isEmpty()) return
        val pendingResult = goAsync()
        Thread {
            try {
                val snapshot = WidgetStats.snapshot(context)
                for (id in appWidgetIds) {
                    render(context, appWidgetManager, id, snapshot)
                }
            } catch (error: Throwable) {
                Log.w(TAG, "Failed to render widget", error)
            } finally {
                pendingResult?.finish()
            }
        }.start()
    }

    private fun render(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        snapshot: WidgetStats.Snapshot,
    ) {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val size = WidgetSize.fromOptions(options)
        val running = DataPlaneControl.isRunning(context)

        val views = RemoteViews(context.packageName, size.layoutRes)
        bindStatus(context, views, running)
        when (size) {
            WidgetSize.SMALL -> Unit
            WidgetSize.MEDIUM -> bindBlockedCount(context, views, snapshot)
            WidgetSize.LARGE -> {
                bindBlockedCount(context, views, snapshot)
                views.setTextViewText(
                    R.id.widget_total_count,
                    countText(context, snapshot.totalToday),
                )
                views.setTextViewText(
                    R.id.widget_rate_value,
                    WidgetStats.formatRate(snapshot.blockedToday, snapshot.totalToday)
                        ?: context.getString(R.string.widget_value_unknown),
                )
                views.setTextViewText(
                    R.id.widget_mode_value,
                    modeLabel(context, DataPlaneControl.workMode(context)),
                )
            }
        }
        bindClicks(context, views)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

    /// Status pill and power button: shared by all three layouts, which use the same view ids.
    private fun bindStatus(context: Context, views: RemoteViews, running: Boolean) {
        views.setTextViewText(
            R.id.widget_status,
            context.getString(
                if (running) R.string.widget_protected else R.string.widget_unprotected,
            ),
        )
        views.setTextColor(
            R.id.widget_status,
            ContextCompat.getColor(
                context,
                if (running) R.color.widget_success else R.color.widget_on_surface_variant,
            ),
        )
        views.setImageViewResource(
            R.id.widget_status_dot,
            if (running) R.drawable.widget_dot_on else R.drawable.widget_dot_off,
        )
        views.setInt(
            R.id.widget_toggle_btn,
            "setBackgroundResource",
            if (running) R.drawable.widget_power_on else R.drawable.widget_power_off,
        )
        views.setImageViewResource(
            R.id.widget_toggle_btn,
            if (running) R.drawable.ic_widget_power_on else R.drawable.ic_widget_power_off,
        )
    }

    private fun bindBlockedCount(
        context: Context,
        views: RemoteViews,
        snapshot: WidgetStats.Snapshot,
    ) {
        views.setTextViewText(
            R.id.widget_blocked_count,
            countText(context, snapshot.blockedToday),
        )
    }

    private fun countText(context: Context, value: Int?): String =
        value?.let(WidgetStats::formatCount)
            ?: context.getString(R.string.widget_value_unknown)

    private fun modeLabel(context: Context, workMode: String): String = context.getString(
        when (workMode) {
            DataPlaneControl.WORK_MODE_DNS -> R.string.widget_mode_server
            DataPlaneControl.WORK_MODE_EXPRESS -> R.string.widget_mode_express
            else -> R.string.widget_mode_normal
        },
    )

    private fun bindClicks(context: Context, views: RemoteViews) {
        val toggleIntent = Intent(context, DitingWidgetToggleReceiver::class.java).apply {
            action = DitingWidgetToggleReceiver.ACTION_TOGGLE
        }
        val togglePending = PendingIntent.getBroadcast(
            context,
            0,
            toggleIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_toggle_btn, togglePending)

        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val openAppPending = PendingIntent.getActivity(
            context,
            1,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        views.setOnClickPendingIntent(R.id.widget_root, openAppPending)
    }

    /// Size classes. Thresholds are in dp and deliberately generous: launchers report the minimum
    /// size the widget can take while it is being resized, and a widget that is too short for the
    /// large layout would clip its footer. The large board is designed for a 4x3 shape.
    private enum class WidgetSize(val layoutRes: Int) {
        SMALL(R.layout.diting_widget_small),
        MEDIUM(R.layout.diting_widget_medium),
        LARGE(R.layout.diting_widget_large);

        companion object {
            fun fromOptions(options: Bundle): WidgetSize {
                val width = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
                val height = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
                // No options yet (first placement): the provider's target cell is 4x2.
                if (width <= 0 || height <= 0) return MEDIUM
                return when {
                    width >= LARGE_MIN_WIDTH && height >= LARGE_MIN_HEIGHT -> LARGE
                    width >= MEDIUM_MIN_WIDTH && height >= MEDIUM_MIN_HEIGHT -> MEDIUM
                    else -> SMALL
                }
            }
        }
    }

    companion object {
        private const val TAG = "DitingWidgetProvider"
        private const val LARGE_MIN_WIDTH = 260
        private const val LARGE_MIN_HEIGHT = 235
        private const val MEDIUM_MIN_WIDTH = 140
        private const val MEDIUM_MIN_HEIGHT = 100

        fun requestRefresh(context: Context) {
            runCatching {
                val appContext = context.applicationContext
                val manager = AppWidgetManager.getInstance(appContext) ?: return
                val ids = manager.getAppWidgetIds(
                    ComponentName(appContext, DitingWidgetProvider::class.java),
                )
                if (ids.isEmpty()) return
                val intent = Intent(appContext, DitingWidgetProvider::class.java).apply {
                    action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
                }
                appContext.sendBroadcast(intent)
            }.onFailure { Log.w(TAG, "Failed to request widget refresh", it) }
        }
    }
}
