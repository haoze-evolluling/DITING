package com.haoze.diting.net

import android.content.Context
import com.haoze.diting.control.DataPlaneControl
import com.haoze.diting.engine.TunnelEngine
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.root.RootDnsService
import com.haoze.diting.vpn.VpnModeProfile

internal object EngineAccess {

    /**
     * 优先取当前工作模式的引擎，避免普通/简洁两个模式的运行时状态串味；
     * 当前模式引擎尚未就绪时，再回退到任何正在运行的引擎。
     */
    fun current(context: Context? = null): TunnelEngine? {
        val preferred: TunnelEngine? = when (context?.let(DataPlaneControl::workMode)) {
            DataPlaneControl.WORK_MODE_NORMAL ->
                runningEngine(VpnModeProfile.NORMAL)
            DataPlaneControl.WORK_MODE_EXPRESS ->
                runningEngine(VpnModeProfile.EXPRESS)
            else -> null
        }
        return preferred
            ?: runningEngine(VpnModeProfile.NORMAL)
            ?: runningEngine(VpnModeProfile.EXPRESS)
            ?: DitingVpnService.engineForDiagnostics()
            ?: ExpressVpnService.engineForDiagnostics()
            ?: RootDnsService.engineForDiagnostics()
    }

    private fun runningEngine(profile: VpnModeProfile): TunnelEngine? =
        profile.runtime.engine?.takeIf { profile.runtime.isRunning }
}
