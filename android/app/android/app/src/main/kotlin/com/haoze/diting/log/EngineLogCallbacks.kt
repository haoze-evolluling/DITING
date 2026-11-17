package com.haoze.diting.log

import android.content.Context
import com.haoze.diting.engine.BatchLogCallback
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.RaceLogCallback

/// Routes the engine's batch DNS log and race batches into the log database of one tunnel mode.
///
/// Every mode runs on the Rust engine since stage 4b-2, so there is one `attach` and one set of
/// callback adapters; each payload goes straight to its writer.
object EngineLogCallbacks {
    fun attach(engine: Engine, context: Context, databaseName: String, logMode: String) {
        engine.setBatchLogCallback(object : BatchLogCallback {
            override fun onDNSQueryBatch(rows: ByteArray) =
                DnsLogWriter.writeBatch(context, databaseName, logMode, rows)
        })
        engine.setRaceLogCallback(object : RaceLogCallback {
            override fun onRaceEvents(rows: ByteArray) =
                RaceLogWriter.writeBatch(context, databaseName, rows)
        })
    }
}
