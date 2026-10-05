package com.haoze.diting.data

import com.haoze.diting.data.dao.AllowRuleDao
import com.haoze.diting.data.dao.BlockRuleDao
import com.haoze.diting.data.dao.CosmeticRuleDao
import com.haoze.diting.data.dao.GoUrlRuleDao
import com.haoze.diting.data.dao.MirrorTemplateDao
import com.haoze.diting.data.dao.RewriteRuleDao
import com.haoze.diting.data.dao.SubscriptionAutoUpdateDao
import com.haoze.diting.data.dao.SubscriptionDao
import com.haoze.diting.data.dao.SubscriptionGroupDao

/**
 * Identifies which isolated rule data set a caller operates on. NORMAL is the
 * original rule database used by VPN mode; DNS_MODE is a fully separate
 * database for the DNS mode malicious-domain filtering, so the two modes never
 * share rule rows, subscription records, or rule settings.
 */
enum class RuleDataset {
    NORMAL,
    EXPRESS,
    DNS_MODE;

    fun prefsName(): String = when (this) {
        NORMAL -> "dns_vpn_prefs"
        EXPRESS -> "diting_express_prefs"
        DNS_MODE -> "diting_dns_mode_prefs"
    }
}

/**
 * Shared runtime DAO surface for DNS cache, query logs, and latency/race logs.
 */
interface DnsRuntimeDataSources {
    fun dnsCacheDao(): com.haoze.diting.data.dao.DnsCacheDao
    fun dnsLogDao(): com.haoze.diting.data.dao.DnsLogDao
    fun raceLogDao(): com.haoze.diting.data.dao.RaceLogDao
    fun bootstrapLogDao(): com.haoze.diting.data.dao.BootstrapLogDao
}


/**
 * The rule-related DAO surface shared by both rule databases. ViewModels and
 * managers depend on this interface instead of AppDatabase so the same code
 * can serve either data set.
 */
interface RuleDataSources {
    fun blockRuleDao(): BlockRuleDao
    fun allowRuleDao(): AllowRuleDao
    fun rewriteRuleDao(): RewriteRuleDao
    fun subscriptionDao(): SubscriptionDao
    fun subscriptionGroupDao(): SubscriptionGroupDao
    fun subscriptionAutoUpdateDao(): SubscriptionAutoUpdateDao
    fun mirrorTemplateDao(): MirrorTemplateDao
    fun goUrlRuleDao(): GoUrlRuleDao
    fun cosmeticRuleDao(): CosmeticRuleDao
}
