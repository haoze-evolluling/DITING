package com.haoze.diting.core.rule

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

/**
 * Builds the `Engine.applyRuleSnapshot` JSON and the rewrite-rule map for one data set.
 *
 * Kotlin owns the SQLite reads (`RuleSnapshotDao`), the DTRI compile call
 * (`MappedSubscriptionRuleIndex`), the stamp file's I/O and the `File` lookups. The classification
 * of the rows, the exported lists and the document itself are built by `rust/diting-rule-core`
 * (see `RuleSnapshotNative`), and so are the index decisions around it: the artifact paths
 * (`RuleIndexLayout`), the header validation, the usable-path filter, the stamp rule, the per-app
 * allowlist normalization, the rule fingerprint text and the rewrite-table de-duplication (see
 * `RuleIndexNative`). There is no second implementation of the rule semantics, so a missing library
 * fails the snapshot build and the caller stops the tunnel rather than running with filtering
 * silently off.
 *
 * The snapshot is built in the service process instead of being shipped through the Intent, so its
 * size no longer depends on the subscription row count and never crosses the Binder limit.
 */
object RuleSnapshotStore {
    private const val TAG = "RuleSnapshotStore"
    private const val STAMP_FILE = "stamp"
    private const val KEY_DOMAIN_RULES_ENABLED = "domain_rules_enabled"
    private const val APP_ALLOWLIST_PREFS = "dns_vpn_prefs"
    private const val KEY_APP_ALLOWLIST_RULES = "app_allowlist_rules_json"

    fun buildSnapshotJson(context: Context, dataset: RuleDataset): String {
        val started = System.nanoTime()
        val prefs = context.getSharedPreferences(dataset.prefsName(), Context.MODE_PRIVATE)
        val filterEnabled = prefs.getBoolean(KEY_DOMAIN_RULES_ENABLED, true)
        val appAllowlist = if (dataset == RuleDataset.NORMAL) readAppAllowlist(context) else emptyMap()

        val dao = RuleSnapshotDao.open(context, dataset.databaseName())
        if (dao == null) {
            Log.w(TAG, "Rule database ${dataset.databaseName()} unavailable; snapshot is empty")
            return RuleSnapshotNative.buildSnapshot(
                RuleSnapshotPayload.encode(emptyInput(filterEnabled)),
            )
        }

        // Every dataset now keeps DTRI artifacts under its own root, so the server mode builds and
        // mmaps the same way the two tunnel modes do.
        val indexDirectory: File? = RuleIndexLayout.rootDirectory(context.filesDir, dataset)

        return try {
            val triesFresh = indexDirectory?.let { isStampCurrent(it, dao) } ?: false
            val block = loadIndexes(dao, indexDirectory, triesFresh, RuleSnapshotDao.RuleKind.BLOCK)
            val allow = loadIndexes(dao, indexDirectory, triesFresh, RuleSnapshotDao.RuleKind.ALLOW)
            // The stamp, the usable flags and the inline-row decision all come from one answer.
            val plan = RuleIndexNative.plan(block, allow)
            if (indexDirectory != null && plan.settled) {
                writeStamp(indexDirectory, dao)
            }
            val json = RuleSnapshotNative.buildSnapshot(
                RuleSnapshotPayload.encode(
                    RuleSnapshotInput(
                        filterEnabled = filterEnabled,
                        blockIndexUsable = plan.block.normalUsable,
                        importantBlockUsable = plan.block.importantUsable,
                        allowIndexUsable = plan.allow.normalUsable,
                        importantAllowUsable = plan.allow.importantUsable,
                        triePaths = triePaths(indexDirectory),
                        appAllowlist = appAllowlist,
                        blockCustom = dao.enabledCustomRules(RuleSnapshotDao.RuleKind.BLOCK),
                        blockSubscription = subscriptionRows(
                            dao,
                            RuleSnapshotDao.RuleKind.BLOCK,
                            plan.block.specialRowsOnly,
                        ),
                        allowCustom = dao.enabledCustomRules(RuleSnapshotDao.RuleKind.ALLOW),
                        allowSubscription = subscriptionRows(
                            dao,
                            RuleSnapshotDao.RuleKind.ALLOW,
                            plan.allow.specialRowsOnly,
                        ),
                    ),
                ),
            )
            // One line: a compile costs seconds on a large subscription and this is the only trace
            // of which path the start took.
            Log.i(
                TAG,
                "[${dataset.name}] snapshot ${json.length}B in ${(System.nanoTime() - started) / 1_000_000}ms " +
                    "tries=${if (triesFresh) "fresh" else "stale"} compiled=${plan.compiled}",
            )
            json
        } finally {
            dao.close()
        }
    }

    /** `Engine.setRewriteRules` flat domain -> target map; '' when empty, matching the Dart encoder. */
    fun buildRewriteRulesJson(context: Context, dataset: RuleDataset): String {
        val dao = RuleSnapshotDao.open(context, dataset.databaseName()) ?: return ""
        return try {
            // Trimmed, blank-free and one row per pattern (oldest wins), then the flat JSON map.
            val targets = JSONObject()
            for ((pattern, target) in RuleIndexNative.rewriteRules(dao.rewriteRules())) {
                targets.put(pattern, target)
            }
            if (targets.length() == 0) "" else targets.toString()
        } finally {
            dao.close()
        }
    }

    /**
     * Recompiles the tries when the database changed since the last build; cheap when the stamp
     * still matches. Called after rule writes so the next service start mmaps instead of compiling.
     */
    fun refreshIndexes(context: Context, dataset: RuleDataset) {
        val indexDirectory = RuleIndexLayout.rootDirectory(context.filesDir, dataset)
        val dao = RuleSnapshotDao.open(context, dataset.databaseName()) ?: return
        try {
            val triesFresh = isStampCurrent(indexDirectory, dao)
            val block = loadIndexes(dao, indexDirectory, triesFresh, RuleSnapshotDao.RuleKind.BLOCK)
            val allow = loadIndexes(dao, indexDirectory, triesFresh, RuleSnapshotDao.RuleKind.ALLOW)
            if (RuleIndexNative.plan(block, allow).settled) {
                writeStamp(indexDirectory, dao)
            }
        } finally {
            dao.close()
        }
    }

    private fun emptyInput(filterEnabled: Boolean) = RuleSnapshotInput(
        filterEnabled = filterEnabled,
        blockIndexUsable = false,
        importantBlockUsable = false,
        allowIndexUsable = false,
        importantAllowUsable = false,
        triePaths = listOf(null, null, null, null),
        appAllowlist = emptyMap(),
        blockCustom = emptyList(),
        blockSubscription = emptyList(),
        allowCustom = emptyList(),
        allowSubscription = emptyList(),
    )

    /** Loads (validating) the two tries of one half, compiling the stale or missing ones. */
    private fun loadIndexes(
        dao: RuleSnapshotDao,
        indexDirectory: File?,
        triesFresh: Boolean,
        kind: RuleSnapshotDao.RuleKind,
    ): RuleIndexHalf {
        val normalFile = indexDirectory?.let {
            if (kind == RuleSnapshotDao.RuleKind.BLOCK) RuleIndexLayout.blockIndex(it) else RuleIndexLayout.allowIndex(it)
        }
        val importantFile = indexDirectory?.let {
            if (kind == RuleSnapshotDao.RuleKind.BLOCK) {
                RuleIndexLayout.blockImportantIndex(it)
            } else {
                RuleIndexLayout.allowImportantIndex(it)
            }
        }
        // The DTRI writer skips the rows a trie cannot hold (wildcards, regexes, app-scoped and
        // `denyallow`/`dnsType` rows) with the same predicate the old Kotlin filter used, so only
        // the `important` split still happens here. `important` is not part of the DTRI payload
        // either: the two files split it, exactly like the legacy loaders.
        val normal = ensureIndex(normalFile, triesFresh) { consume ->
            val importantFilter = if (kind == RuleSnapshotDao.RuleKind.BLOCK) false else null
            dao.forEachSubscriptionRulePage(kind, importantFilter) { rule ->
                if (!rule.important) consume(rule)
            }
        }
        val important = ensureIndex(importantFile, triesFresh) { consume ->
            dao.forEachSubscriptionRulePage(kind, important = true) { rule ->
                if (rule.important) consume(rule)
            }
        }
        return RuleIndexHalf(normal, important)
    }

    /**
     * The subscription rows the snapshot needs. When both tries are usable the plain rules already
     * live in the DTRI files, so only the rows that must stay inline are read.
     */
    private fun subscriptionRows(
        dao: RuleSnapshotDao,
        kind: RuleSnapshotDao.RuleKind,
        specialRowsOnly: Boolean,
    ): List<EnabledRule> {
        if (specialRowsOnly) {
            return dao.enabledSpecialSubscriptionRules(kind)
        }
        val rows = ArrayList<EnabledRule>()
        when (kind) {
            RuleSnapshotDao.RuleKind.BLOCK -> {
                dao.forEachSubscriptionRulePage(kind, important = false) { rows += it }
                dao.forEachSubscriptionRulePage(kind, important = true) { rows += it }
            }
            RuleSnapshotDao.RuleKind.ALLOW -> dao.forEachSubscriptionRulePage(kind) { rows += it }
        }
        return rows
    }

    /** Loads (validating) an existing trie or compiles a fresh one; `FAILED` means the compile
     *  ran but produced nothing usable, so callers must not refresh the stamp. */
    private fun ensureIndex(
        file: File?,
        triesFresh: Boolean,
        compile: ((EnabledRule) -> Unit) -> Unit,
    ): IndexOutcome {
        if (file == null) return IndexOutcome.NOT_INDEXED
        if (triesFresh && file.exists() && file.length() > 0) {
            val loaded = runCatching { MappedSubscriptionRuleIndex.load(file) }
                .onFailure { Log.w(TAG, "Existing subscription index invalid, will recompile", it) }
                .getOrNull()
            if (loaded != null) {
                loaded.close()
                return IndexOutcome.LOADED
            }
        }
        val compiled = runCatching { MappedSubscriptionRuleIndex.compileAndLoad(file, compile) }
            .onFailure { error -> Log.e(TAG, "Failed to compile subscription index (${file.name})", error) }
            .getOrNull()
        compiled?.close()
        return if (compiled != null) IndexOutcome.COMPILED else IndexOutcome.FAILED
    }

    /** The four trie paths, exported only when the file exists and is non-empty. */
    private fun triePaths(indexDirectory: File?): List<String?> {
        val files = if (indexDirectory == null) {
            List(4) { "" to (false to 0L) }
        } else {
            listOf(
                RuleIndexLayout.blockIndex(indexDirectory),
                RuleIndexLayout.blockImportantIndex(indexDirectory),
                RuleIndexLayout.allowIndex(indexDirectory),
                RuleIndexLayout.allowImportantIndex(indexDirectory),
            ).map { file -> file.absolutePath to (file.exists() to file.length()) }
        }
        return RuleIndexNative.triePaths(
            indexDirectoryOk = indexDirectory != null && indexDirectory.isDirectory,
            files = files,
        )
    }

    /** Package -> allowed domains from the user's per-app allowlist prefs. */
    private fun readAppAllowlist(context: Context): Map<String, Set<String>> {
        val raw = runCatching {
            context.getSharedPreferences(APP_ALLOWLIST_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_APP_ALLOWLIST_RULES, null)
        }.getOrNull() ?: return emptyMap()
        if (raw.isNullOrBlank()) return emptyMap()
        val parsed = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
        val packages = ArrayList<Pair<String, List<String>>>(parsed.length())
        for (key in parsed.keys()) {
            val arr = parsed.optJSONArray(key) ?: continue
            packages += key to List(arr.length()) { arr.optString(it) }
        }
        // The kernel trims, drops the blanks, de-duplicates and keeps the insertion order.
        val result = LinkedHashMap<String, Set<String>>()
        for ((packageName, domains) in RuleIndexNative.appAllowlist(packages)) {
            result[packageName] = domains.toSet()
        }
        return result
    }

    // The tries are derived data: the stamp records the rule-table fingerprint they were compiled
    // from, so any rule write (import, toggle, delete) invalidates them and forces one recompile.
    // It must not use the database file size/mtime: the same file carries the request-log tables,
    // which the tunnel writes continuously, so every start would look stale and recompile.

    // The stamp is only refreshed when a compile actually happened and nothing failed: writing it
    // after a failed compile would make the next start trust a stale trie file as fresh. That rule
    // is `RuleIndexNative.plan`'s `settled`.

    private fun stampFile(indexDirectory: File) = File(indexDirectory, STAMP_FILE)

    private fun isStampCurrent(indexDirectory: File, dao: RuleSnapshotDao): Boolean {
        val stamp = runCatching { stampFile(indexDirectory).readText().trim() }.getOrNull() ?: return false
        return stamp == dao.ruleFingerprint()
    }

    private fun writeStamp(indexDirectory: File, dao: RuleSnapshotDao) {
        runCatching {
            indexDirectory.mkdirs()
            stampFile(indexDirectory).writeText(dao.ruleFingerprint())
        }.onFailure { Log.w(TAG, "Unable to write rule index stamp", it) }
    }
}
