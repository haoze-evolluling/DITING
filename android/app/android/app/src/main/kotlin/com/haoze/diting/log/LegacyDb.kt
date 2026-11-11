package com.haoze.diting.log

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.util.Log
import java.io.File
import java.util.Collections
import java.util.WeakHashMap
import java.util.concurrent.ConcurrentHashMap

/// Owns the one writable connection per database file used by the native readers and writers.
///
/// Opening a connection per log event is what broke 2.1.7: every `openDatabase` runs Android's
/// journal-mode probe (`PRAGMA journal_mode`), which needs the schema, so while the Flutter side
/// held the write lock every open threw `SQLiteDatabaseLockedException` and the event was dropped
/// (183 attempts, zero successes, four minutes). One long-lived connection plus `busy_timeout`
/// turns that into a short wait on the same connection the writers already share.
internal object LegacyDb {
    private const val TAG = "LegacyDb"
    private const val BUSY_TIMEOUT_MS = 5_000

    /// Outcome of [open]. Writers must tell [Absent] (nothing to write to yet) from [Unavailable]
    /// (locked right now): only the latter is worth retrying, and only the former is worth dropping.
    sealed interface Open {
        class Ready(val db: SQLiteDatabase) : Open

        /// The file does not exist yet (fresh install): writing now would race schema creation.
        data object Absent : Open

        /// Locked or otherwise unopenable; the caller keeps its buffer and retries with backoff.
        class Unavailable(val cause: Throwable?) : Open
    }

    /// Result of [tableState]. 2.1.9 folded every query failure into "missing", so one
    /// `SQLITE_BUSY` on `sqlite_master` latched a writer into dropping every row it received.
    enum class TableState { PRESENT, MISSING, ERROR }

    private val connections = HashMap<String, SQLiteDatabase>()

    /// Tables seen on a connection. Only positive answers are cached: the app never drops a log
    /// table, while a missing one can appear once the Dart side creates the schema.
    private val knownTables: MutableMap<SQLiteDatabase, MutableSet<String>> =
        Collections.synchronizedMap(WeakHashMap())

    @Synchronized
    fun open(context: Context, databaseName: String): Open {
        connections[databaseName]?.let { cached ->
            if (cached.isOpen) return Open.Ready(cached)
            // Closed behind our back (a reader that still owns a handle, or a service restart).
            connections.remove(databaseName)
        }
        val path = context.getDatabasePath(databaseName)
        if (!File(path.path).exists()) return Open.Absent
        return runCatching {
            SQLiteDatabase.openDatabase(
                path.path,
                null,
                SQLiteDatabase.OPEN_READWRITE or SQLiteDatabase.ENABLE_WRITE_AHEAD_LOGGING,
            ).also { db ->
                db.setBusyTimeout(BUSY_TIMEOUT_MS)
                // WAL + NORMAL syncs at checkpoints, not on every log-batch commit (Room did the
                // same for 1.4.3); a power cut can lose the last commits but never corrupts.
                db.pragmaString("PRAGMA synchronous = NORMAL")
                val journal = db.pragmaString("PRAGMA journal_mode")
                // One line per open (the connection is cached, so opens are rare): the next log
                // export can tell whether the connection really is WAL with a busy timeout.
                Log.i(
                    TAG,
                    "opened $databaseName journal=$journal " +
                        "busy=${db.pragmaLong("PRAGMA busy_timeout")}ms v${db.version}",
                )
                if (!journal.equals("wal", ignoreCase = true)) {
                    // A non-WAL file makes every Dart read block these writers' commits.
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

    /// `PRAGMA busy_timeout = N` returns a row, so `execSQL` rejects it ("Queries can be performed
    /// using SQLiteDatabase query or rawQuery methods only") — that turned every 2.1.8 open into a
    /// failure. A query consumes the row instead, and the whole thing stays best-effort: a pragma
    /// that does not stick must never invalidate a connection that already opened.
    private fun SQLiteDatabase.setBusyTimeout(timeoutMs: Int) {
        runCatching {
            rawQuery("PRAGMA busy_timeout = $timeoutMs", null).use { it.moveToFirst() }
        }.onFailure { DbWriteHealth.warn("LegacyDb", "busy_timeout not applied", it) }
    }

    private fun SQLiteDatabase.pragmaString(sql: String): String = runCatching {
        rawQuery(sql, null).use { if (it.moveToFirst()) it.getString(0) else "?" }
    }.getOrDefault("?")

    private fun SQLiteDatabase.pragmaLong(sql: String): Long = runCatching {
        rawQuery(sql, null).use { if (it.moveToFirst()) it.getLong(0) else -1L }
    }.getOrDefault(-1L)

    /// Live read-back for the troubleshooting page: whether the connection is actually WAL and
    /// actually has a busy timeout. Counters alone cannot tell "no failures yet" from "no writes".
    fun probe(context: Context, databaseName: String): Map<String, Any> {
        val opened = open(context, databaseName)
        if (opened !is Open.Ready) {
            val cause = (opened as? Open.Unavailable)?.cause
            val text = cause?.let { "${it.javaClass.simpleName}: ${it.message}" }
                ?: "database file missing"
            return mapOf(
                "probeDatabase" to databaseName,
                "probeOk" to false,
                // A missing file is normal before the first run creates the schema.
                "probeAbsent" to (opened is Open.Absent),
                "probeCause" to text,
            )
        }
        val db = opened.db
        return mapOf(
            "probeDatabase" to databaseName,
            "probeOk" to true,
            "probeAbsent" to false,
            "probeJournalMode" to db.pragmaString("PRAGMA journal_mode"),
            "probeBusyTimeoutMs" to db.pragmaLong("PRAGMA busy_timeout"),
            "probeUserVersion" to db.version,
            "probeCause" to "",
        )
    }

    /// For readers that only need "the database, or null".
    fun writable(context: Context, databaseName: String): SQLiteDatabase? =
        (open(context, databaseName) as? Open.Ready)?.db

    /// Releases every cached connection; the next [open] re-opens on demand.
    @Synchronized
    fun closeAll() {
        for ((name, db) in connections) {
            runCatching { db.close() }
                .onFailure { DbWriteHealth.warn("LegacyDb", "close $name failed", it) }
        }
        connections.clear()
    }

    /// Whether [table] exists. A failed lookup (locked, I/O) is [TableState.ERROR], never
    /// [TableState.MISSING]: writers retry the former and only drop rows on the latter.
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

    /// For readers, where "not readable right now" and "missing" both mean "skip".
    fun hasTable(db: SQLiteDatabase, table: String): Boolean =
        tableState(db, table) == TableState.PRESENT
}
