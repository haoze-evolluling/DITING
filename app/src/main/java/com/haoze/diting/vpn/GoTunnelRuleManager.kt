package com.haoze.diting.vpn

import android.content.Context
import android.util.Log
import com.haoze.diting.ui.settings.AppRulesSettingsStore
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import tunnel.Engine
import java.io.File

/**
 * Manages synchronizing DNS and HTTP rules (rule snapshots, CNAME redirects,
 * request rules, HTTPS bypass passthrough, and app allowlists) to the Go [Engine].
 */
internal class GoTunnelRuleManager(
    private val context: Context,
    private val vpnService: DnsVpnService,
    private val engine: Engine,
    private val dnsPolicy: DomainPolicy,
    private val cnameRewriteRuleManager: RewriteRuleManager,
    private val goUrlRuleManager: GoUrlRuleManager,
    private val inspectionEnabled: Boolean,
    private val ruleIndexDirectory: File?,
    private val packageUidProvider: (String) -> Int?
) {

    /**
     * Pushes a rule snapshot one-way to the Go-side local rule decision
     * engine (includes static subscription paths and small rule sets).
     */
    fun pushRuleSnapshot() {
        val snapshotJson = dnsPolicy.buildRuleSnapshotJson(ruleIndexDirectory)
        runCatching {
            val err = engine.applyRuleSnapshot(snapshotJson)
            if (!err.isNullOrBlank()) {
                Log.w(TAG, "applyRuleSnapshot error: $err")
            } else {
                Log.d(TAG, "applyRuleSnapshot succeeded")
            }
        }.onFailure { Log.w(TAG, "Failed to push rule snapshot to Go engine", it) }
    }

    fun updateRewriteRules() {
        dnsPolicy.invalidateCache()
        updateRewriteMap()
        updateRequestRules()
        updatePassthroughRules()
        pushRuleSnapshot()
    }

    fun updatePassthroughRules() {
        runCatching {
            val presetRules = DefaultWhitelistSeeder.parseAssetWhitelist(context).map { it.first }
            val customBypassRules = AppRulesSettingsStore.getHttpsBypassRules(context)
            val combined = (presetRules + customBypassRules).filter { it.isNotBlank() }
            engine.setExtraPassthroughSuffixes(combined.joinToString("\n"))
        }.onFailure { Log.w(TAG, "Failed to update HTTPS bypass rules", it) }
    }

    /**
     * Pushes the merged rewrite map to the Go engine: IPv4/IPv6 answers are
     * gated on the DNS-stage domain rules switch (they are answered before
     * any filtering in the Go DNS pipeline), while CNAME redirects stay
     * gated on HTTPS inspection plus the address rules switch because the
     * redirect itself runs inside the MITM flow.
     */
    fun updateRewriteMap() {
        runCatching {
            val merged = JSONObject()
            if (AppRulesSettingsStore.isDomainRulesEnabled(vpnService)) {
                cnameRewriteRuleManager.ipRewrites().forEach { (domain, targets) ->
                    merged.put(domain, JSONArray(targets))
                }
            }
            if (inspectionEnabled && AppRulesSettingsStore.isAddressRulesEnabled(vpnService)) {
                cnameRewriteRuleManager.cnameRedirects().forEach { (domain, target) ->
                    if (!merged.has(domain)) merged.put(domain, target)
                }
            }
            engine.setRewriteRules(merged.toString())
        }.onFailure { Log.w(TAG, "Failed to push rewrite rules to Go engine", it) }
    }

    fun updateRequestRules() {
        if (!inspectionEnabled || !AppRulesSettingsStore.isAddressRulesEnabled(vpnService)) {
            engine.setRequestRules("")
            return
        }
        engine.setRequestRules(runBlocking { goUrlRuleManager.jsonSnapshot() })
    }

    @Synchronized
    fun syncAppAllowlist(rules: Map<String, Set<String>>) {
        val root = JSONObject()
        for ((pkg, domains) in rules) {
            val uid = packageUidProvider(pkg) ?: continue
            val validDomains = domains.filter { it.isNotBlank() }
            val arr = JSONArray()
            validDomains.forEach { arr.put(it) }
            root.put(uid.toString(), arr)
        }
        engine.setAppAllowlist(root.toString())
    }

    private companion object {
        const val TAG = "GoTunnelRuleManager"
    }
}
