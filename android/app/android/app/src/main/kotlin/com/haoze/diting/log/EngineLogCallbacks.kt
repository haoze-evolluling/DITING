package com.haoze.diting.log

import android.content.Context
import com.haoze.diting.engine.BatchLogCallback
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.RaceLogCallback

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
