package com.haoze.diting.core.rule

import android.content.Context
import com.haoze.diting.engine.TunnelEngine

/// Builds a dataset's rule snapshot and rewrite rules and applies them to the engine. Callers run
/// it off the main thread: a stale index means a trie compile that can take seconds.
object EngineRuleLoader {
    /// Throws when the snapshot cannot be built or the policy kernel rejects it; callers report the
    /// failure and stop the tunnel instead of running with filtering silently off.
    ///
    /// Every mode implements [`TunnelEngine`], which is all this needs (`applyRuleSnapshot` and
    /// `setRewriteRules`).
    fun apply(context: Context, engine: TunnelEngine, dataset: RuleDataset, tag: String) {
        val snapshot = RuleSnapshotStore.buildSnapshotJson(context, dataset)
        val snapshotError = engine.applyRuleSnapshot(snapshot)
        check(snapshotError.isBlank()) { "$tag: applyRuleSnapshot failed: $snapshotError" }
        val rewriteRules = RuleSnapshotStore.buildRewriteRulesJson(context, dataset)
        if (rewriteRules.isNotBlank()) {
            engine.setRewriteRules(rewriteRules)
        }
    }
}
