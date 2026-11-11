package com.haoze.diting.log

import android.content.Context
import com.haoze.diting.engine.BatchLogCallback
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.RaceLogCallback

/// Routes the engine's batch DNS log and race results into the log database of one tunnel mode.
///
/// Every mode runs on the Rust engine since stage 4b-2, so there is one `attach` and one set of
/// callback adapters; the payload calls live in [Writer.onBatch] / [Writer.onRace].
object EngineLogCallbacks {
    fun attach(engine: Engine, context: Context, databaseName: String, logMode: String) {
        val writer = Writer(context, databaseName, logMode)
        engine.setBatchLogCallback(object : BatchLogCallback {
            override fun onDNSQueryBatch(jsonLogs: String) = writer.onBatch(jsonLogs)
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
            ) = writer.onRace(
                queryName,
                queryType,
                strategy,
                providerCount,
                success,
                elapsedMs,
                selectedProviderID,
                selectedElapsedMs,
                winnerProviderID,
                winnerElapsedMs,
                fallbackUsed,
                fallbackSuccess,
                errorMessage,
            )
        })
    }

    /// The one destination of every engine log stream.
    private class Writer(
        private val context: Context,
        private val databaseName: String,
        private val logMode: String,
    ) {
        fun onBatch(jsonLogs: String) {
            DnsLogWriter.writeBatch(context, databaseName, logMode, jsonLogs)
        }

        @Suppress("LongParameterList")
        fun onRace(
            queryName: String,
            queryType: Long,
            strategy: String,
            providerCount: Long,
            success: Boolean,
            elapsedMs: Long,
            selectedProviderId: String,
            selectedElapsedMs: Long,
            winnerProviderId: String,
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
                selectedProviderId = selectedProviderId,
                selectedElapsedMs = selectedElapsedMs,
                winnerProviderId = winnerProviderId,
                winnerElapsedMs = winnerElapsedMs,
                fallbackUsed = fallbackUsed,
                fallbackSuccess = fallbackSuccess,
                errorMessage = errorMessage,
            )
        }
    }
}
