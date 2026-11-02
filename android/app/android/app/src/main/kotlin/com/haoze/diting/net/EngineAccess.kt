package com.haoze.diting.net

import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.server.DitingDnsServerService
import tunnel.Engine

/// Finds the Go engine backing a tunnel; R8 renames private fields in release, hence the accessors.
internal object EngineAccess {

    fun current(): Engine? =
        DitingVpnService.engineForDiagnostics()
            ?: ExpressVpnService.engineForDiagnostics()
            ?: DitingDnsServerService.engineForDiagnostics()
}
