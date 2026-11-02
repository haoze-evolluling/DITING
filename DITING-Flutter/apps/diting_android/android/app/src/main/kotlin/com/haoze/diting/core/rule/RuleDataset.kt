package com.haoze.diting.core.rule

/**
 * Identifies which isolated rule data set a caller operates on, ported from the legacy app.
 * NORMAL is the original rule database used by VPN mode; DNS_MODE is a fully separate database
 * for the DNS server mode, so the two modes never share rule rows or rule settings.
 */
enum class RuleDataset {
    NORMAL,
    EXPRESS,
    DNS_MODE;

    /** The legacy SharedPreferences file holding per-dataset rule settings. */
    fun prefsName(): String = when (this) {
        NORMAL -> "dns_vpn_prefs"
        EXPRESS -> "diting_express_prefs"
        DNS_MODE -> "diting_dns_mode_prefs"
    }

    /** The legacy SQLite database file holding this data set's rule tables. */
    fun databaseName(): String = when (this) {
        NORMAL -> "diting_database"
        EXPRESS -> "diting_express"
        DNS_MODE -> "diting_dns_rules"
    }
}
