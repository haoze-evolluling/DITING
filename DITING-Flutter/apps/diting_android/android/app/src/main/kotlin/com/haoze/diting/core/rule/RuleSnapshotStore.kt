package com.haoze.diting.core.rule

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Builds the `Engine.applyRuleSnapshot` JSON in the service process, ported from the legacy
 * `DomainPolicyEngine.buildRuleSnapshotJson` wiring: subscription plain rules travel as mmap trie
 * file paths, everything else (custom, wildcard, app-scoped, inverted, special, disabled) stays
 * inline. The snapshot is built here instead of being shipped through the Intent, so its size no
 * longer depends on the subscription row count and never crosses the Binder transaction limit.
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
            return emptySnapshotJson(filterEnabled)
        }

        val indexDirectory = if (dataset == RuleDataset.DNS_MODE) {
            // Legacy DNS server mode never used index files: it keeps every rule inline and is
            // applied in-process, which is safe because nothing crosses Binder here either.
            null
        } else {
            RuleIndexLayout.rootDirectory(context.filesDir, dataset)
        }

        return try {
            val triesFresh = indexDirectory?.let { isStampCurrent(it, dao) } ?: false
            val blockLoaded = BlockRuleLoader.load(dao, indexDirectory, triesFresh)
            val allowLoaded = AllowRuleLoader.load(dao, indexDirectory, triesFresh)
            if (indexDirectory != null && indexesSettled(blockLoaded.compiledAnyIndex, blockLoaded.compileFailure, allowLoaded.compileFailure)) {
                writeStamp(indexDirectory, dao)
            }
            val json = buildJson(filterEnabled, appAllowlist, indexDirectory, blockLoaded, allowLoaded)
            // One line: a compile costs seconds on a large subscription and this is the only trace
            // of which path the start took.
            Log.i(
                TAG,
                "[${dataset.name}] snapshot ${json.length}B in ${(System.nanoTime() - started) / 1_000_000}ms " +
                    "tries=${if (triesFresh) "fresh" else "stale"} compiled=${blockLoaded.compiledAnyIndex || allowLoaded.compiledAnyIndex}",
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
            val targets = JSONObject()
            for ((pattern, target) in dao.rewriteRules()) {
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
        if (dataset == RuleDataset.DNS_MODE) return
        val indexDirectory = RuleIndexLayout.rootDirectory(context.filesDir, dataset)
        val dao = RuleSnapshotDao.open(context, dataset.databaseName()) ?: return
        try {
            val triesFresh = isStampCurrent(indexDirectory, dao)
            val blockLoaded = BlockRuleLoader.load(dao, indexDirectory, triesFresh)
            val allowLoaded = AllowRuleLoader.load(dao, indexDirectory, triesFresh)
            if (indexesSettled(blockLoaded.compiledAnyIndex, blockLoaded.compileFailure, allowLoaded.compileFailure)) {
                writeStamp(indexDirectory, dao)
            }
        } finally {
            dao.close()
        }
    }

    /** JSON shape mirrors `DomainPolicyEngine.buildRuleSnapshotJson` field for field. */
    private fun buildJson(
        filterEnabled: Boolean,
        appAllowlist: Map<String, Set<String>>,
        indexDirectory: File?,
        blockLoaded: LoadedBlockRules,
        allowLoaded: LoadedAllowRules,
    ): String {
        val blockSnapshot = BlockRuleLoader.export(blockLoaded)
        val allowSnapshot = AllowRuleLoader.export(allowLoaded)

        val root = JSONObject()
        root.put("filterEnabled", filterEnabled)

        if (indexDirectory != null && indexDirectory.isDirectory) {
            val blockTrie = RuleIndexLayout.blockIndex(indexDirectory)
            if (blockTrie.exists() && blockTrie.length() > 0) {
                root.put("blockTriePath", blockTrie.absolutePath)
            }
            val impBlockTrie = RuleIndexLayout.blockImportantIndex(indexDirectory)
            if (impBlockTrie.exists() && impBlockTrie.length() > 0) {
                root.put("importantBlockTriePath", impBlockTrie.absolutePath)
            }
            val allowTrie = RuleIndexLayout.allowIndex(indexDirectory)
            if (allowTrie.exists() && allowTrie.length() > 0) {
                root.put("allowTriePath", allowTrie.absolutePath)
            }
            // Important allow rules of subscriptions live only in this index:
            // AllowRuleLoader drops them from the exported fallback list once the
            // index exists, so omitting the path silently loses them.
            val impAllowTrie = RuleIndexLayout.allowImportantIndex(indexDirectory)
            if (impAllowTrie.exists() && impAllowTrie.length() > 0) {
                root.put("importantAllowTriePath", impAllowTrie.absolutePath)
            }
        }

        val globalAllowArr = JSONArray()
        allowSnapshot.globalAllow.forEach { globalAllowArr.put(it) }
        root.put("globalAllow", globalAllowArr)

        val globalBlockArr = JSONArray()
        blockSnapshot.globalBlock.forEach { globalBlockArr.put(it) }
        root.put("globalBlock", globalBlockArr)

        val globalImpArr = JSONArray()
        blockSnapshot.globalImportant.forEach { globalImpArr.put(it) }
        root.put("globalImportant", globalImpArr)

        // appRules: map of pkg -> { allow: [...], block: [...], important: [...] }; the Flutter app
        // also folds the user per-app allowlist prefs into `allow` (normal dataset only).
        val allPkgs = LinkedHashSet<String>()
        allPkgs.addAll(allowSnapshot.appRules.keys)
        allPkgs.addAll(blockSnapshot.appRules.keys)
        allPkgs.addAll(appAllowlist.keys)

        val appRulesObj = JSONObject()
        for (pkg in allPkgs) {
            val appObj = JSONObject()
            val allows = LinkedHashSet<String>()
            allows.addAll(allowSnapshot.appRules[pkg].orEmpty())
            allows.addAll(appAllowlist[pkg].orEmpty())
            val blockRules = blockSnapshot.appRules[pkg]

            val allowArr = JSONArray()
            allows.forEach { allowArr.put(it) }
            appObj.put("allow", allowArr)

            val blockArr = JSONArray()
            blockRules?.block.orEmpty().forEach { blockArr.put(it) }
            appObj.put("block", blockArr)

            val impArr = JSONArray()
            blockRules?.important.orEmpty().forEach { impArr.put(it) }
            appObj.put("important", impArr)

            appRulesObj.put(pkg, appObj)
        }
        root.put("appRules", appRulesObj)

        val invBlockArr = JSONArray()
        for (rule in blockSnapshot.invertedRules) {
            val invObj = JSONObject()
            invObj.put("pattern", rule.pattern)
            invObj.put("source", rule.source)
            invObj.put("important", rule.important)
            val excArr = JSONArray()
            rule.excludedApps.forEach { excArr.put(it) }
            invObj.put("excludedApps", excArr)
            invBlockArr.put(invObj)
        }
        root.put("invertedBlock", invBlockArr)

        val invAllowArr = JSONArray()
        for (rule in allowSnapshot.invertedRules) {
            val invObj = JSONObject()
            invObj.put("pattern", rule.pattern)
            val excArr = JSONArray()
            rule.excludedApps.forEach { excArr.put(it) }
            invObj.put("excludedApps", excArr)
            invAllowArr.put(invObj)
        }
        root.put("invertedAllow", invAllowArr)

        val disabledArr = JSONArray()
        blockSnapshot.disabledRules.forEach { disabledArr.put(it) }
        root.put("disabledRules", disabledArr)

        val specialBlockArr = JSONArray()
        for (rule in blockSnapshot.specialRules) {
            specialBlockArr.put(specialRuleJson(rule, withSource = true))
        }
        root.put("specialBlock", specialBlockArr)

        val specialAllowArr = JSONArray()
        for (rule in allowSnapshot.specialRules) {
            specialAllowArr.put(specialRuleJson(rule, withSource = false))
        }
        root.put("specialAllow", specialAllowArr)

        return root.toString()
    }

    private fun specialRuleJson(rule: ExportedSpecialRule, withSource: Boolean): JSONObject {
        val obj = JSONObject()
        obj.put("pattern", rule.pattern)
        if (withSource) obj.put("source", rule.source)
        obj.put("important", rule.important)
        if (rule.appScope != null) obj.put("appScope", rule.appScope)
        obj.put("appInverted", rule.appInverted)
        obj.put("isWildcard", rule.isWildcard)
        if (rule.denyallow != null) obj.put("denyallow", rule.denyallow)
        obj.put("isRegex", rule.isRegex)
        if (rule.dnsType != null) obj.put("dnsType", rule.dnsType)
        return obj
    }

    private fun emptySnapshotJson(filterEnabled: Boolean): String {
        val root = JSONObject()
        root.put("filterEnabled", filterEnabled)
        root.put("globalAllow", JSONArray())
        root.put("globalBlock", JSONArray())
        root.put("globalImportant", JSONArray())
        root.put("appRules", JSONObject())
        root.put("invertedBlock", JSONArray())
        root.put("invertedAllow", JSONArray())
        root.put("disabledRules", JSONArray())
        root.put("specialBlock", JSONArray())
        root.put("specialAllow", JSONArray())
        return root.toString()
    }

    /** Package -> allowed domains from the user's per-app allowlist prefs. */
    private fun readAppAllowlist(context: Context): Map<String, Set<String>> {
        val raw = runCatching {
            context.getSharedPreferences(APP_ALLOWLIST_PREFS, Context.MODE_PRIVATE)
                .getString(KEY_APP_ALLOWLIST_RULES, null)
        }.getOrNull() ?: return emptyMap()
        if (raw.isNullOrBlank()) return emptyMap()
        val parsed = runCatching { JSONObject(raw) }.getOrNull() ?: return emptyMap()
        val result = LinkedHashMap<String, Set<String>>()
        for (key in parsed.keys()) {
            val domains = mutableSetOf<String>()
            val arr = parsed.optJSONArray(key) ?: continue
            for (i in 0 until arr.length()) {
                val domain = arr.optString(i).trim()
                if (domain.isNotEmpty()) domains += domain
            }
            if (domains.isNotEmpty() && key.isNotBlank()) result[key] = domains
        }
        return result
    }

    // The tries are derived data: the stamp records the rule-table fingerprint they were compiled
    // from, so any rule write (import, toggle, delete) invalidates them and forces one recompile.
    // It must not use the database file size/mtime: the same file carries the request-log tables,
    // which the tunnel writes continuously, so every start would look stale and recompile.

    /** The stamp is only refreshed when a compile actually happened and nothing failed: writing it
     *  after a failed compile would make the next start trust a stale trie file as fresh. */
    private fun indexesSettled(compiledAny: Boolean, blockFailed: Boolean, allowFailed: Boolean): Boolean =
        compiledAny && !blockFailed && !allowFailed

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
