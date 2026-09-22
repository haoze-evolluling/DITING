package com.haoze.diting.ui.transfer

import com.haoze.diting.data.entity.MirrorTemplateEntity
import com.haoze.diting.data.entity.RuleScope
import com.haoze.diting.data.entity.SubscriptionGroupEntity
import com.haoze.diting.data.entity.SubscriptionKind
import com.haoze.diting.vpn.AdGuardRuleParser
import com.haoze.diting.vpn.AllowListManager
import com.haoze.diting.vpn.BlockListManager
import com.haoze.diting.vpn.GoUrlRuleManager
import com.haoze.diting.vpn.RewriteRule
import com.haoze.diting.vpn.RewriteRuleManager
import com.haoze.diting.vpn.SubscriptionManager
import java.io.File

/**
 * Handles importing mirror templates, subscription groups, remote subscriptions,
 * and custom block/allow/rewrite/address rules.
 */
internal class RuleConfigImporter(private val session: ImportSessionContext) {

    private val context get() = session.context
    private val database get() = session.database
    private val ruleIndexDir by lazy { File(context.filesDir, "rule-index") }

    private fun subscriptionManager(scope: RuleScope = RuleScope.DNS) = SubscriptionManager(
        database,
        database.subscriptionDao(),
        BlockListManager(database.blockRuleDao(), ruleIndexDir, scope = scope, reloadCacheAfterChanges = false),
        AllowListManager(database.allowRuleDao(), ruleIndexDir, scope = scope, reloadCacheAfterChanges = false),
        RewriteRuleManager(database.rewriteRuleDao(), ruleIndexDir, scope, reloadCacheAfterChanges = false),
        scope,
        context.cacheDir
    )

    suspend fun importRules(config: TransferConfig) {
        // Mirror templates
        val mirrorDao = database.mirrorTemplateDao()
        config.mirrorTemplates.forEach { template ->
            val item = "镜像模板：${template.name}"
            val detail = "镜像模板：${template.name}"
            val existing = mirrorDao.byName(template.name)
            if (existing != null) {
                session.skipped++
                session.skippedDetails.add(detail)
                session.complete(item, "跳过 $detail (已存在)")
            } else {
                mirrorDao.insert(MirrorTemplateEntity(name = template.name, template = template.template))
                session.added++
                session.addedDetails.add(detail)
                session.complete(item, "新增 $detail")
            }
        }

        // Subscription groups
        val groupDao = database.subscriptionGroupDao()
        val importedGroupIds = mutableMapOf<String, Long>()
        config.subscriptionGroups.forEach { group ->
            val existing = groupDao.byName(group.name)
            val id = existing?.id ?: groupDao.insert(
                SubscriptionGroupEntity(
                    name = group.name,
                    autoUpdateEnabled = group.autoUpdateEnabled
                )
            )
            importedGroupIds[group.name.lowercase()] = id
        }

        // Remote subscriptions
        val existingSubscriptionKeys = database.subscriptionDao().allRemote()
            .map { subscriptionKey(it.url, RuleScope.DNS, it.kind) }.toMutableSet()
        config.subscriptions.forEach { entry ->
            val item = "规则订阅：${entry.name}"
            val detail = "规则订阅：${entry.name}"
            val entryKind = SubscriptionKind.normalize(entry.kind)
            val key = subscriptionKey(entry.url, entry.scope, entryKind)
            if (!existingSubscriptionKeys.add(key)) {
                database.subscriptionDao().byUrlAndKind(entry.url, entryKind)?.let { existingSub ->
                    if (existingSub.enabled != entry.enabled) {
                        database.subscriptionDao().setEnabled(existingSub.id, entry.enabled)
                    }
                }
                session.skipped++
                session.skippedDetails.add(detail)
                session.complete(item, "跳过 $detail (已存在)")
            } else {
                val result = subscriptionManager(entry.scope).addRemoteSubscription(
                    url = entry.url,
                    name = entry.name,
                    groupId = entry.groupName?.let { importedGroupIds[it.lowercase()] },
                    kind = entryKind,
                    mirrorTemplate = entry.mirrorTemplate,
                    mirrorFallback = entry.mirrorFallback
                )
                if (result.isFailure) {
                    session.failed++
                    session.failedDetails.add(detail)
                    session.complete(item, "添加 $detail 失败")
                } else {
                    if (!entry.enabled) {
                        database.subscriptionDao().byUrlAndKind(entry.url, entryKind)?.let {
                            database.subscriptionDao().setEnabled(it.id, false)
                        }
                    }
                    session.added++
                    session.subscriptionsAdded++
                    session.addedDetails.add(detail)
                    session.complete(item, "新增 $detail")
                }
            }
        }

        // Custom domain, rewrite & address rules
        val blockManager = BlockListManager(database.blockRuleDao(), ruleIndexDir, scope = RuleScope.DNS, reloadCacheAfterChanges = false)
        val allowManager = AllowListManager(database.allowRuleDao(), ruleIndexDir, scope = RuleScope.DNS, reloadCacheAfterChanges = false)
        val rewriteManager = RewriteRuleManager(database.rewriteRuleDao(), ruleIndexDir, RuleScope.DNS, reloadCacheAfterChanges = false)
        val goUrlRuleManager = GoUrlRuleManager(database.goUrlRuleDao())

        if (config.customBlockRules.isNotEmpty()) {
            val parsedBlock = config.customBlockRules.mapNotNull { rule ->
                AdGuardRuleParser.parseLine(rule.rawLine.ifEmpty { rule.pattern })?.let { parsed ->
                    parsed to rule.enabled
                }
            }
            val enabledRules = parsedBlock.filter { it.second }.map { it.first }
            val disabledRules = parsedBlock.filterNot { it.second }.map { it.first }
            val insertedEnabled = if (enabledRules.isNotEmpty()) blockManager.addRulesBatch(enabledRules, "useradd", enabled = true, refreshCache = false) else 0
            val insertedDisabled = if (disabledRules.isNotEmpty()) blockManager.addRulesBatch(disabledRules, "useradd", enabled = false, refreshCache = false) else 0
            val inserted = insertedEnabled + insertedDisabled
            session.added += inserted
            val skippedCount = config.customBlockRules.size - inserted
            session.skipped += skippedCount
            session.customRulesAdded += inserted
            config.customBlockRules.forEach { rule ->
                val id = database.blockRuleDao().idByPattern(rule.pattern, rule.important, rule.appScope, rule.appInverted)
                if (id > 0) {
                    database.blockRuleDao().setEnabled(id, rule.enabled)
                    database.blockRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                session.complete("自定义域名屏蔽规则：${rule.pattern}", "处理自定义域名屏蔽规则：${rule.pattern}")
            }
            if (inserted > 0) session.addedDetails.add("自定义域名屏蔽规则 ($inserted 条)")
            if (skippedCount > 0) session.skippedDetails.add("自定义域名屏蔽规则 ($skippedCount 条已存在)")
        }

        if (config.customAllowRules.isNotEmpty()) {
            val parsedAllow = config.customAllowRules.mapNotNull { rule ->
                AdGuardRuleParser.parseAllowLine(rule.rawLine.ifEmpty { rule.pattern })?.let { parsed ->
                    parsed to rule.enabled
                }
            }
            val enabledRules = parsedAllow.filter { it.second }.map { it.first }
            val disabledRules = parsedAllow.filterNot { it.second }.map { it.first }
            val insertedEnabled = if (enabledRules.isNotEmpty()) allowManager.addRulesBatch(enabledRules, "useradd", enabled = true, refreshCache = false) else 0
            val insertedDisabled = if (disabledRules.isNotEmpty()) allowManager.addRulesBatch(disabledRules, "useradd", enabled = false, refreshCache = false) else 0
            val inserted = insertedEnabled + insertedDisabled
            session.added += inserted
            val skippedCount = config.customAllowRules.size - inserted
            session.skipped += skippedCount
            session.customRulesAdded += inserted
            config.customAllowRules.forEach { rule ->
                val id = database.allowRuleDao().idByPattern(rule.pattern, rule.important, rule.appScope, rule.appInverted)
                if (id > 0) {
                    database.allowRuleDao().setEnabled(id, rule.enabled)
                    database.allowRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                session.complete("自定义域名放行规则：${rule.pattern}", "处理自定义域名放行规则：${rule.pattern}")
            }
            if (inserted > 0) session.addedDetails.add("自定义域名放行规则 ($inserted 条)")
            if (skippedCount > 0) session.skippedDetails.add("自定义域名放行规则 ($skippedCount 条已存在)")
        }

        if (config.customRewriteDomainRules.isNotEmpty()) {
            val enabledList = config.customRewriteDomainRules.filter { it.enabled }.map {
                RewriteRule(pattern = it.pattern, targetType = it.targetType, targetValue = it.targetValue, rawLine = it.rawLine)
            }
            val disabledList = config.customRewriteDomainRules.filterNot { it.enabled }.map {
                RewriteRule(pattern = it.pattern, targetType = it.targetType, targetValue = it.targetValue, rawLine = it.rawLine)
            }
            val insertedEnabled = if (enabledList.isNotEmpty()) rewriteManager.addRules(enabledList, "useradd", enabled = true, refreshCache = false) else 0
            val insertedDisabled = if (disabledList.isNotEmpty()) rewriteManager.addRules(disabledList, "useradd", enabled = false, refreshCache = false) else 0
            val inserted = insertedEnabled + insertedDisabled
            session.added += inserted
            val skippedCount = config.customRewriteDomainRules.size - inserted
            session.skipped += skippedCount
            session.customRulesAdded += inserted
            config.customRewriteDomainRules.forEach { rule ->
                val id = database.rewriteRuleDao().idByKey(rule.pattern, rule.targetType, rule.targetValue)
                if (id > 0) {
                    database.rewriteRuleDao().setEnabled(id, rule.enabled)
                    database.rewriteRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                session.complete("自定义复写域名规则：${rule.pattern}", "处理自定义复写域名规则：${rule.pattern}")
            }
            if (inserted > 0) session.addedDetails.add("自定义复写域名规则 ($inserted 条)")
            if (skippedCount > 0) session.skippedDetails.add("自定义复写域名规则 ($skippedCount 条已存在)")
        }

        if (config.customRewriteCnameRules.isNotEmpty()) {
            val enabledList = config.customRewriteCnameRules.filter { it.enabled }.map {
                RewriteRule(pattern = it.pattern, targetType = it.targetType, targetValue = it.targetValue, rawLine = it.rawLine)
            }
            val disabledList = config.customRewriteCnameRules.filterNot { it.enabled }.map {
                RewriteRule(pattern = it.pattern, targetType = it.targetType, targetValue = it.targetValue, rawLine = it.rawLine)
            }
            val insertedEnabled = if (enabledList.isNotEmpty()) rewriteManager.addRules(enabledList, "useradd", enabled = true, refreshCache = false) else 0
            val insertedDisabled = if (disabledList.isNotEmpty()) rewriteManager.addRules(disabledList, "useradd", enabled = false, refreshCache = false) else 0
            val inserted = insertedEnabled + insertedDisabled
            session.added += inserted
            val skippedCount = config.customRewriteCnameRules.size - inserted
            session.skipped += skippedCount
            session.customRulesAdded += inserted
            config.customRewriteCnameRules.forEach { rule ->
                val id = database.rewriteRuleDao().idByKey(rule.pattern, rule.targetType, rule.targetValue)
                if (id > 0) {
                    database.rewriteRuleDao().setEnabled(id, rule.enabled)
                    database.rewriteRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                session.complete("自定义复写 CNAME 规则：${rule.pattern}", "处理自定义复写 CNAME 规则：${rule.pattern}")
            }
            if (inserted > 0) session.addedDetails.add("自定义复写 CNAME 规则 ($inserted 条)")
            if (skippedCount > 0) session.skippedDetails.add("自定义复写 CNAME 规则 ($skippedCount 条已存在)")
        }

        if (config.customAddressRules.isNotEmpty()) {
            var urlInserted = 0
            config.customAddressRules.forEach { rule ->
                val line = if (rule.rawLine.isNotBlank()) rule.rawLine else if (rule.kind.equals("allow", true)) "@@${rule.pattern}" else rule.pattern
                val ok = goUrlRuleManager.addRule(line)
                val id = database.goUrlRuleDao().idByPattern(rule.pattern, rule.kind)
                if (id > 0) {
                    database.goUrlRuleDao().setEnabled(id, rule.enabled)
                    database.goUrlRuleDao().setSourceEnabledByRuleId(id, rule.enabled)
                }
                if (ok) {
                    urlInserted++
                    session.addedDetails.add("自定义地址规则：${rule.pattern}")
                    session.complete("自定义地址规则：${rule.pattern}", "新增自定义地址规则：${rule.pattern}")
                } else {
                    session.skippedDetails.add("自定义地址规则：${rule.pattern} (已存在)")
                    session.complete("自定义地址规则：${rule.pattern}", "跳过自定义地址规则：${rule.pattern} (已存在)")
                }
            }
            session.added += urlInserted
            session.skipped += config.customAddressRules.size - urlInserted
            session.customRulesAdded += urlInserted
        }
    }

    private fun subscriptionKey(url: String, scope: RuleScope, kind: String) =
        "${scope.storageValue}:${SubscriptionKind.normalize(kind)}:${url.trim().lowercase()}"
}
