package com.haoze.diting.net

import com.haoze.diting.engine.TunnelEngine
import com.haoze.diting.express.ExpressVpnService
import com.haoze.diting.normal.DitingVpnService

/// Finds the engine backing a mode; R8 renames private fields in release, hence the accessors.
///
/// Both modes run on the Rust engine since stage 4b-2 and implement the shared interface, so this
/// is only a priority order: the tunnel that is up, then the other one.
internal object EngineAccess {

    fun current(): TunnelEngine? =
        DitingVpnService.engineForDiagnostics()
            ?: ExpressVpnService.engineForDiagnostics()
}
