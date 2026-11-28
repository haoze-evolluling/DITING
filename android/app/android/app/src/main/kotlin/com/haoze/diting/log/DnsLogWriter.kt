package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteStatement

object DnsLogWriter {
    const val MODE_ALL = "all"
    const val MODE_BLOCKED_AND_ERRORS = "blocked_and_errors"
    const val MODE_OFF = "off"

    private const val TABLE = "dns_log"

    private const val INSERT_SQL = "INSERT OR IGNORE INTO dns_log " +
        "(timestamp, queryName, queryType, result, message, cached, blockSubscriptionId, packageName, " +
        "clientIp, clientName, protocol, upstreamProvider, rcode, cacheHit, durationMs, ttl) " +
        "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

    fun writeBatch(context: Context, databaseName: String, mode: String, packed: ByteArray) {
        if (packed.size <= Int.SIZE_BYTES) return
        LogTableWriters.of(context, databaseName, TABLE, "diting-dns-log", INSERT_SQL, ::bindRow)
            .submitDnsBatch(RequestStats.kernel, mode, packed)
    }

    private fun bindRow(statement: SQLiteStatement, row: ByteArray) {
        val reader = LogPayload.Reader(row)
        statement.bindLong(1, reader.i64())
        statement.bindString(2, reader.string())
        statement.bindLong(3, reader.i32().toLong())
        statement.bindString(4, reader.string())
        val message = reader.optionalString()
        if (message == null) statement.bindNull(5) else statement.bindString(5, message)
        statement.bindLong(6, if (reader.u8() != 0) 1 else 0)
        val subscription = reader.optionalLong()
        if (subscription == null) statement.bindNull(7) else statement.bindLong(7, subscription)
        val packageName = reader.optionalString()
        if (packageName == null) statement.bindNull(8) else statement.bindString(8, packageName)
        statement.bindString(9, reader.string())
        statement.bindString(10, reader.string())
        statement.bindString(11, reader.string())
        statement.bindString(12, reader.string())
        statement.bindString(13, reader.string())
        statement.bindString(14, reader.string())
        statement.bindLong(15, reader.i64())
        statement.bindLong(16, reader.i64())
    }
}
