package com.haoze.diting.log

import android.content.Context
import tunnel.BatchLogCallback
import tunnel.Engine
import tunnel.RaceLogCallback

/// Routes the engine's batch DNS log and race results into the log database of one tunnel mode.
object EngineLogCallbacks {
    fun attach(engine: Engine, context: Context, databaseName: String, logMode: String) {
        engine.setBatchLogCallback(object : BatchLogCallback {
            override fun onDNSQueryBatch(jsonLogs: String) {
                DnsLogWriter.writeBatch(context, databaseName, logMode, jsonLogs)
            }
        })
        engine.setRaceLogCallback(object : RaceLogCallback {
            override fun onRaceResult(
                queryName: String,
                queryType: Long,
                strategy: String,
                providerCount: Long,
                success: Boolean,
                elapsedMs: Long,
                selectedProviderID: String,
                selectedElapsedMs: Long,
                winnerProviderID: String,
                winnerElapsedMs: Long,
                fallbackUsed: Boolean,
                fallbackSuccess: Boolean,
                errorMessage: String,
            ) {
                RaceLogWriter.write(
                    context,
                    databaseName,
                    queryName = queryName,
                    queryType = queryType.toInt(),
                    strategy = strategy,
                    providerCount = providerCount.toInt(),
                    success = success,
                    elapsedMs = elapsedMs,
                    selectedProviderId = selectedProviderID,
                    selectedElapsedMs = selectedElapsedMs,
                    winnerProviderId = winnerProviderID,
                    winnerElapsedMs = winnerElapsedMs,
                    fallbackUsed = fallbackUsed,
                    fallbackSuccess = fallbackSuccess,
                    errorMessage = errorMessage,
                )
            }
        })
    }
}
