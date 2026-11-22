package com.haoze.diting.net

import com.haoze.diting.engine.TunnelEngine
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.root.RootDnsService
import com.haoze.diting.vpn.VpnModeProfile

internal object EngineAccess {

    /** 优先取正在运行模式的引擎，避免两个模式的运行时状态串味。 */
    fun current(): TunnelEngine? =
        VpnModeProfile.NORMAL.runtime.engine?.takeIf {
            VpnModeProfile.NORMAL.runtime.isRunning
        }
            ?: VpnModeProfile.EXPRESS.runtime.engine?.takeIf {
                VpnModeProfile.EXPRESS.runtime.isRunning
            }
            ?: DitingVpnService.engineForDiagnostics()
            ?: ExpressVpnService.engineForDiagnostics()
            ?: RootDnsService.engineForDiagnostics()
}
