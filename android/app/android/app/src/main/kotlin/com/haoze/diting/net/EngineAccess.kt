package com.haoze.diting.net

import com.haoze.diting.engine.TunnelEngine
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.root.RootDnsService

internal object EngineAccess {

    fun current(): TunnelEngine? =
        DitingVpnService.engineForDiagnostics()
            ?: ExpressVpnService.engineForDiagnostics()
            ?: RootDnsService.engineForDiagnostics()
}
