package com.haoze.diting.control

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.haoze.diting.server.ServerDnsService
import com.haoze.diting.server.ServerPreference

/**
 * 开机或应用更新后按用户设置恢复上次使用的数据面。
 *
 * 服务器模式使用自己的「开机自启动」开关，并直接启动 [ServerDnsService]；
 * 普通/简洁隧道与 Root DNS 接管复用 [DataPlaneControl.start] 的恢复逻辑。
 * 两者都以已同意用户协议为前提，缺少授权时静默跳过，不打扰用户。
 */
class BootAutoStartReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        val appContext: Context = context.applicationContext
        if (!DataPlaneControl.isAgreementAccepted(appContext)) return
        val mode: String = DataPlaneControl.workMode(appContext)
        if (mode == DataPlaneControl.WORK_MODE_SERVER) {
            if (!ServerPreference.autoStart(appContext)) return
            val pendingResult: BroadcastReceiver.PendingResult = goAsync()
            Thread {
                try {
                    ServerDnsService.start(
                        appContext,
                        ServerPreference.preferRoot(appContext),
                        ServerPreference.lastDnsConfig(appContext),
                    )
                } catch (error: Throwable) {
                    Log.w(TAG, "服务器模式开机自启动失败", error)
                } finally {
                    pendingResult.finish()
                }
            }.start()
            return
        }
        if (!DataPlaneControl.autoStartOnBootEnabled(appContext)) return
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
