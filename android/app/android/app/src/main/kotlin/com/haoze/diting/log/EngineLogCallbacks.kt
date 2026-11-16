package com.haoze.diting.log

import android.content.Context
import com.haoze.diting.engine.BatchLogCallback
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.RaceLogCallback

/// Routes the engine's batch DNS log and race batches into the log database of one tunnel mode.
///
/// Every mode runs on the Rust engine since stage 4b-2, so there is one `attach` and one set of
/// callback adapters; the payload calls live in [Writer.onBatch] / [Writer.onRaceBatch].
object EngineLogCallbacks {
    fun attach(engine: Engine, context: Context, databaseName: String, logMode: String) {
        val writer = Writer(context, databaseName, logMode)
        engine.setBatchLogCallback(object : BatchLogCallback {
            override fun onDNSQueryBatch(rows: ByteArray) = writer.onBatch(rows)
        })
        engine.setRaceLogCallback(object : RaceLogCallback {
            override fun onRaceEvents(rows: ByteArray) = writer.onRaceBatch(rows)
        })
    }

    /// The one destination of every engine log stream.
    private class Writer(
        private val context: Context,
        private val databaseName: String,
        private val logMode: String,
    ) {
        fun onBatch(rows: ByteArray) {
            DnsLogWriter.writeBatch(context, databaseName, logMode, rows)
        }

        fun onRaceBatch(rows: ByteArray) {
            RaceLogWriter.writeBatch(context, databaseName, rows)
        }
    }
}
