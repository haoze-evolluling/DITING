package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.util.Collections
import java.util.WeakHashMap
import java.util.concurrent.ConcurrentHashMap

internal object AppDatabase {
    private const val TAG = "AppDatabase"
    private const val BUSY_TIMEOUT_MS = 5_000

    sealed interface Open {
        class Ready(val db: SQLiteDatabase) : Open

        data object Absent : Open

        class Unavailable(val cause: Throwable?) : Open
    }

    enum class TableState { PRESENT, MISSING, ERROR }

    private val connections = HashMap<String, SQLiteDatabase>()

    private val knownTables: MutableMap<SQLiteDatabase, MutableSet<String>> =
        Collections.synchronizedMap(WeakHashMap())

    @Synchronized
    fun open(context: Context, databaseName: String): Open {
        connections[databaseName]?.let { cached ->
            if (cached.isOpen) return Open.Ready(cached)
            connections.remove(databaseName)
        }
        val path = context.getDatabasePath(databaseName)
        if (!path.exists()) return Open.Absent
        return runCatching {
            SQLiteDatabase.openDatabase(
                path.path,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING,
            ).also { db ->
                db.setBusyTimeout(BUSY_TIMEOUT_MS)
                db.pragmaString("PRAGMA synchronous = NORMAL")
                val journal = db.pragmaString("PRAGMA journal_mode")
                Log.i(
                    TAG,
                    "opened $databaseName journal=$journal " +
                        "busy=${db.pragmaLong("PRAGMA busy_timeout")}ms v${db.version}",
                )
                if (!journal.equals("wal", ignoreCase = true)) {
                    DbWriteHealth.warn(TAG, "$databaseName is not in WAL mode (journal=$journal)")
                }
            }
        }.fold(
            onSuccess = { db ->
                connections[databaseName] = db
                Open.Ready(db)
            },
            onFailure = { error ->
                DbWriteHealth.onOpenFailure(databaseName, error)
                Open.Unavailable(error)
            },
        )
    }

    private fun SQLiteDatabase.setBusyTimeout(timeoutMs: Int) {
        runCatching {
            rawQuery("PRAGMA busy_timeout = $timeoutMs", null).use { it.moveToFirst() }
        }.onFailure { DbWriteHealth.warn("AppDatabase", "busy_timeout not applied", it) }
    }

    private fun SQLiteDatabase.pragmaString(sql: String): String = runCatching {
        rawQuery(sql, null).use { if (it.moveToFirst()) it.getString(0) else "?" }
    }.getOrDefault("?")

    private fun SQLiteDatabase.pragmaLong(sql: String): Long = runCatching {
        rawQuery(sql, null).use { if (it.moveToFirst()) it.getLong(0) else -1L }
    }.getOrDefault(-1L)

    fun probe(context: Context, databaseName: String): Map<String, Any> =
        when (val opened = open(context, databaseName)) {
            is Open.Ready -> mapOf(
                "probeDatabase" to databaseName,
                "probeOk" to true,
                "probeAbsent" to false,
                "probeJournalMode" to opened.db.pragmaString("PRAGMA journal_mode"),
                "probeBusyTimeoutMs" to opened.db.pragmaLong("PRAGMA busy_timeout"),
                "probeUserVersion" to opened.db.version,
                "probeCause" to "",
            )
            else -> {
                val cause = (opened as? Open.Unavailable)?.cause
                val text = cause?.let { "${it.javaClass.simpleName}: ${it.message}" }
                    ?: "database file missing"
                mapOf(
                    "probeDatabase" to databaseName,
                    "probeOk" to false,
                    "probeAbsent" to (opened is Open.Absent),
                    "probeCause" to text,
                )
            }
        }

    fun writable(context: Context, databaseName: String): SQLiteDatabase? =
        (open(context, databaseName) as? Open.Ready)?.db

    @Synchronized
    fun closeAll() {
        for ((name, db) in connections) {
            runCatching { db.close() }
                .onFailure { DbWriteHealth.warn("AppDatabase", "close $name failed", it) }
        }
        connections.clear()
    }

    fun tableState(db: SQLiteDatabase, table: String): TableState {
        if (knownTables[db]?.contains(table) == true) return TableState.PRESENT
        return try {
            val found = db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
                arrayOf(table),
            ).use { it.moveToFirst() }
            if (found) {
                synchronized(knownTables) {
                    knownTables.getOrPut(db) { ConcurrentHashMap.newKeySet() }.add(table)
                }
                TableState.PRESENT
            } else {
                TableState.MISSING
            }
        } catch (t: Throwable) {
            DbWriteHealth.warn(TAG, "table lookup for $table failed", t)
            TableState.ERROR
        }
    }

    fun hasTable(db: SQLiteDatabase, table: String): Boolean =
        tableState(db, table) == TableState.PRESENT
}
