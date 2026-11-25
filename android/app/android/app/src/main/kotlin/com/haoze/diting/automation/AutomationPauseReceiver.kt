package com.haoze.diting.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 应用内通知动作入口：不导出，也不受“允许外部自动化控制”开关影响，
 * 避免通知栏的暂停按钮被其它应用伪造。
 */
class AutomationPauseReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext: Context = context.applicationContext
        when (intent.action) {
            AutomationContract.ACTION_PAUSE -> {
                val minutes: Int = intent.getIntExtra(
                    AutomationContract.EXTRA_PAUSE_MINUTES,
                    AutomationContract.DEFAULT_PAUSE_MINUTES,
                )
                AutomationPause.pause(appContext, minutes)
            }
            AutomationContract.ACTION_CANCEL_PAUSE -> AutomationPause.resume(appContext)
            else -> return
        }
        StateBroadcaster.broadcast(appContext)
    }
}
