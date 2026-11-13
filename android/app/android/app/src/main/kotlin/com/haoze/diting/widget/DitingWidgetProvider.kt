package com.haoze.diting.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.view.View
import android.widget.RemoteViews
import com.haoze.diting.MainActivity
import com.haoze.diting.R
import com.haoze.diting.control.DataPlaneControl

/// Home screen widget: protection state, today's blocked count and a one-tap toggle.
///
/// Modelled on BlockAds' `AdBlockWidgetProvider`: a single responsive layout, an unexported
/// receiver for the toggle (so no other app can flip the tunnel through a broadcast) and the
/// database read moved off the main thread with `goAsync`.
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
                val blocked = WidgetStats.blockedToday(context)
                for (id in appWidgetIds) {
                    render(context, appWidgetManager, id, blocked)
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
        blockedToday: Int?,
    ) {
        val options = appWidgetManager.getAppWidgetOptions(appWidgetId)
        val minWidth = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minHeight = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val expanded = minWidth >= EXPANDED_MIN_WIDTH_DP && minHeight >= EXPANDED_MIN_HEIGHT_DP
        val running = DataPlaneControl.isRunning(context)

        val views = RemoteViews(context.packageName, R.layout.diting_widget)
        views.setTextViewText(
            R.id.widget_status,
            context.getString(
                if (running) R.string.widget_protected else R.string.widget_unprotected,
            ),
        )
        views.setInt(
            R.id.widget_toggle_btn,
            "setBackgroundResource",
            if (running) R.drawable.widget_toggle_on else R.drawable.widget_toggle_off,
        )
        if (expanded) {
            views.setViewVisibility(R.id.widget_blocked_row, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_blocked_count,
                blockedToday?.toString() ?: context.getString(R.string.widget_value_unknown),
            )
        } else {
            views.setViewVisibility(R.id.widget_blocked_row, View.GONE)
        }
        bindClicks(context, views)
        appWidgetManager.updateAppWidget(appWidgetId, views)
    }

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

    companion object {
        private const val TAG = "DitingWidgetProvider"
        private const val EXPANDED_MIN_WIDTH_DP = 160
        private const val EXPANDED_MIN_HEIGHT_DP = 90

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
