package com.haoze.diting.core.rule

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.io.File

object RuleSnapshotStore {
    private const val TAG = "RuleSnapshotStore"
    private const val STAMP_FILE = "stamp"

    // 旧版本可能写入过“编译期间被新写入污染”的指纹，升级时强制重建一次。
    private const val STAMP_VERSION = "2"
    private const val KEY_DOMAIN_RULES_ENABLED = "domain_rules_enabled"
    private const val APP_ALLOWLIST_PREFS = "dns_vpn_prefs"
    private const val KEY_APP_ALLOWLIST_RULES = "app_allowlist_rules_json"

    fun buildSnapshot(context: Context, dataset: RuleDataset): ByteArray {
        val started = System.nanoTime()
        val prefs = context.getSharedPreferences(dataset.prefsName(), Context.MODE_PRIVATE)
        val filterEnabled = prefs.getBoolean(KEY_DOMAIN_RULES_ENABLED, true)
        // 应用白名单规则是全局 UI 设置，两种模式都要生效（规则与日志才按数据集隔离）。
        val appAllowlist = readAppAllowlist(context)

        val dao = RuleSnapshotDao.open(context, dataset.rulesDatabase())
            ?: throw IllegalStateException(
                "rule database ${dataset.rulesDatabase()} unavailable",
            )

        val indexDirectory = RuleIndexLayout.rootDirectory(context.filesDir, dataset)

        return try {
            // 指纹只取一次：编译结束后再比对，避免编译期间有新写入时
            // 用“更新后的指纹”给“旧索引”盖章导致索引被误判为最新。
            val fingerprint = dao.ruleFingerprint()
            val triesFresh = isStampCurrent(indexDirectory, fingerprint)
            val block = loadIndexes(dao, indexDirectory, triesFresh, RuleSnapshotDao.RuleKind.BLOCK)
            val allow = loadIndexes(dao, indexDirectory, triesFresh, RuleSnapshotDao.RuleKind.ALLOW)
            val plan = RuleIndexNative.plan(block, allow)
            if (plan.settled && dao.ruleFingerprint() == fingerprint) {
                writeStamp(indexDirectory, fingerprint)
            }
            val document = RuleSnapshotNative.buildSnapshotBytes(
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
            Log.i(
                TAG,
                "[${dataset.name}] snapshot ${document.size}B in ${(System.nanoTime() - started) / 1_000_000}ms " +
                    "tries=${if (triesFresh) "fresh" else "stale"} compiled=${plan.compiled}",
            )
            document
        } finally {
            dao.close()
        }
    }

    fun buildSnapshotJson(context: Context, dataset: RuleDataset): String =
        buildSnapshot(context, dataset).toString(Charsets.UTF_8)

    fun buildRewriteRulesJson(context: Context, dataset: RuleDataset): String {
        val dao = RuleSnapshotDao.open(context, dataset.rulesDatabase()) ?: return ""
        return try {
            val targets = JSONObject()
            for ((pattern, target) in RuleIndexNative.rewriteRules(dao.rewriteRules())) {
                targets.put(pattern, target)
            }
            if (targets.length() == 0) "" else targets.toString()
        } finally {
            dao.close()
        }
    }

    fun refreshIndexes(context: Context, dataset: RuleDataset) {
        val indexDirectory = RuleIndexLayout.rootDirectory(context.filesDir, dataset)
        val dao = RuleSnapshotDao.open(context, dataset.rulesDatabase()) ?: return
        try {
            val fingerprint = dao.ruleFingerprint()
            val triesFresh = isStampCurrent(indexDirectory, fingerprint)
            val block = loadIndexes(dao, indexDirectory, triesFresh, RuleSnapshotDao.RuleKind.BLOCK)
            val allow = loadIndexes(dao, indexDirectory, triesFresh, RuleSnapshotDao.RuleKind.ALLOW)
            if (RuleIndexNative.plan(block, allow).settled &&
                dao.ruleFingerprint() == fingerprint
            ) {
                writeStamp(indexDirectory, fingerprint)
            }
        } finally {
            dao.close()
        }
    }

    private fun loadIndexes(
        dao: RuleSnapshotDao,
        indexDirectory: File,
        triesFresh: Boolean,
        kind: RuleSnapshotDao.RuleKind,
    ): RuleIndexHalf {
        val isBlock = kind == RuleSnapshotDao.RuleKind.BLOCK
        val normalFile = if (isBlock) {
            RuleIndexLayout.blockIndex(indexDirectory)
        } else {
            RuleIndexLayout.allowIndex(indexDirectory)
        }
        val importantFile = if (isBlock) {
            RuleIndexLayout.blockImportantIndex(indexDirectory)
        } else {
            RuleIndexLayout.allowImportantIndex(indexDirectory)
        }
        // 屏蔽规则按域名后缀匹配，父域名已存在时子域名条目冗余；允许规则保持原样。
        val normal = ensureIndex(normalFile, triesFresh, isBlock) { consume ->
            val importantFilter = if (isBlock) false else null
            dao.forEachSubscriptionRulePage(kind, importantFilter) { rule ->
                if (!rule.important) consume(rule)
            }
        }
        val important = ensureIndex(importantFile, triesFresh, isBlock) { consume ->
            dao.forEachSubscriptionRulePage(kind, important = true) { rule ->
                if (rule.important) consume(rule)
            }
        }
        return RuleIndexHalf(normal, important)
    }

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

    private fun ensureIndex(
        file: File,
        triesFresh: Boolean,
        dedupeHierarchy: Boolean,
        compile: ((EnabledRule) -> Unit) -> Unit,
    ): IndexOutcome {
        if (triesFresh && file.exists() && file.length() > 0) {
            val loaded = runCatching { MappedSubscriptionRuleIndex.load(file) }
                .onFailure { Log.w(TAG, "Existing subscription index invalid, will recompile", it) }
                .getOrNull()
            if (loaded != null) {
                loaded.close()
                return IndexOutcome.LOADED
            }
        }
        val compiled = runCatching {
            MappedSubscriptionRuleIndex.compileAndLoad(file, dedupeHierarchy, compile)
        }
            .onFailure { error -> Log.e(TAG, "Failed to compile subscription index (${file.name})", error) }
            .getOrNull()
        compiled?.close()
        return if (compiled != null) IndexOutcome.COMPILED else IndexOutcome.FAILED
    }

    private fun triePaths(indexDirectory: File): List<String?> {
        val files = listOf(
            RuleIndexLayout.blockIndex(indexDirectory),
            RuleIndexLayout.blockImportantIndex(indexDirectory),
            RuleIndexLayout.allowIndex(indexDirectory),
            RuleIndexLayout.allowImportantIndex(indexDirectory),
        ).map { file -> file.absolutePath to (file.exists() to file.length()) }
        return RuleIndexNative.triePaths(
            indexDirectoryOk = indexDirectory.isDirectory,
            files = files,
        )
    }

    private fun readAppAllowlist(context: Context): Map<String, Set<String>> {
        val raw = runCatching {
            context.getSharedPreferences(APP_ALLOWLIST_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_APP_ALLOWLIST_RULES, null)
        }.getOrNull() ?: return emptyMap()
        if (raw.isBlank()) return emptyMap()
        val parsed = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
        val packages = ArrayList<Pair<String, List<String>>>(parsed.length())
        for (key in parsed.keys()) {
            val arr = parsed.optJSONArray(key) ?: continue
            packages += key to List(arr.length()) { arr.optString(it) }
        }
        val result = LinkedHashMap<String, Set<String>>()
        for ((packageName, domains) in RuleIndexNative.appAllowlist(packages)) {
            result[packageName] = domains.toSet()
        }
        return result
    }



    private fun stampFile(indexDirectory: File) = File(indexDirectory, STAMP_FILE)

    private fun isStampCurrent(indexDirectory: File, fingerprint: String): Boolean {
        val stamp = runCatching { stampFile(indexDirectory).readText().trim() }.getOrNull() ?: return false
        return stamp == stampValue(fingerprint)
    }

    private fun writeStamp(indexDirectory: File, fingerprint: String) {
        runCatching {
            indexDirectory.mkdirs()
            stampFile(indexDirectory).writeText(stampValue(fingerprint))
        }.onFailure { Log.w(TAG, "Unable to write rule index stamp", it) }
    }

    private fun stampValue(fingerprint: String) = "$STAMP_VERSION:$fingerprint"
}
