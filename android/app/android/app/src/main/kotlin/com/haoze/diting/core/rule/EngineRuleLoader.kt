package com.haoze.diting.core.rule

import android.content.Context
import com.haoze.diting.engine.TunnelEngine

object EngineRuleLoader {
    fun apply(context: Context, engine: TunnelEngine, dataset: RuleDataset, tag: String) {
        val snapshot = RuleSnapshotStore.buildSnapshot(context, dataset)
        val snapshotError = engine.applyRuleSnapshot(snapshot)
        check(snapshotError.isBlank()) { "$tag: applyRuleSnapshot failed: $snapshotError" }
        val rewriteRules = RuleSnapshotStore.buildRewriteRulesJson(context, dataset)
        if (rewriteRules.isNotBlank()) {
            engine.setRewriteRules(rewriteRules)
        }
    }
}
