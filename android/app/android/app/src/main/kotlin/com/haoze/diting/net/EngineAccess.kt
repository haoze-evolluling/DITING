package com.haoze.diting.net

import com.haoze.diting.engine.TunnelEngine
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService
import com.haoze.diting.server.DitingDnsServerService

/// Finds the engine backing a mode; R8 renames private fields in release, hence the accessors.
///
/// Every mode runs on the Rust engine since stage 4b-2 and implements the shared interface, so this
/// is only a priority order: the tunnel that is up, then the other one, then the DNS server.
internal object EngineAccess {

    fun current(): TunnelEngine? =
        DitingVpnService.engineForDiagnostics()
            ?: ExpressVpnService.engineForDiagnostics()
            ?: DitingDnsServerService.engineForDiagnostics()
}
