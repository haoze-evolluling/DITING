package com.haoze.diting.control

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机后按用户设置恢复上次使用的数据面。
 *
 * 只处理 BOOT_COMPLETED：普通/简洁隧道、Express 与 Root DNS 接管都复用
 * [DataPlaneControl.start] 的恢复逻辑；服务器模式与缺少授权时跳过，不打扰用户。
 */
class BootAutoStartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val appContext: Context = context.applicationContext
        if (!DataPlaneControl.autoStartOnBootEnabled(appContext)) return
        if (!DataPlaneControl.isAgreementAccepted(appContext)) return
        if (DataPlaneControl.workMode(appContext) == DataPlaneControl.WORK_MODE_SERVER) return
        val pendingResult: BroadcastReceiver.PendingResult = goAsync()
        Thread {
            try {
                val result: DataPlaneControl.Result = DataPlaneControl.start(appContext)
                if (result == DataPlaneControl.Result.NeedsApp) {
                    Log.i(TAG, "开机自启动跳过：缺少 VPN 授权或启动参数")
                }
            } catch (error: Throwable) {
                Log.w(TAG, "开机自启动失败", error)
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    companion object {
        private const val TAG = "BootAutoStartReceiver"
    }
}
