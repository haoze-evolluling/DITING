package com.haoze.diting.core.rule

import android.content.Context
import android.util.Log
import tunnel.Engine

/// Builds a dataset's rule snapshot and rewrite rules and applies them to the engine. Callers run
/// it off the main thread: a stale index means a trie compile that can take seconds.
object EngineRuleLoader {
    /// Throws when the snapshot cannot be built; a rejected snapshot is only logged under [tag].
    fun apply(context: Context, engine: Engine, dataset: RuleDataset, tag: String) {
        val snapshot = RuleSnapshotStore.buildSnapshotJson(context, dataset)
        val snapshotError = engine.applyRuleSnapshot(snapshot)
        if (snapshotError.isNotBlank()) {
            Log.w(tag, "applyRuleSnapshot failed: $snapshotError")
        }
        val rewriteRules = RuleSnapshotStore.buildRewriteRulesJson(context, dataset)
        if (rewriteRules.isNotBlank()) {
            engine.setRewriteRules(rewriteRules)
        }
    }
}
