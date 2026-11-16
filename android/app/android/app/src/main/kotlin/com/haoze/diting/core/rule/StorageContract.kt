package com.haoze.diting.core.rule

/**
 * File names and lifecycle keys of the V2 stores.
 *
 * Mirrors `shared/lib/data/db/storage_contract.dart`. Native readers and writers resolve a mode's
 * rules and logs file directly from [RuleDataset]; the layout marker no longer selects a name.
 */
object StorageContract {
    const val NORMAL_RULES = "diting_normal_rules_v2"
    const val NORMAL_LOGS = "diting_normal_logs_v2"
    const val EXPRESS_RULES = "diting_express_rules_v2"
    const val EXPRESS_LOGS = "diting_express_logs_v2"
    const val DNS_RULES = "diting_dns_rules_v2"
    const val DNS_LOGS = "diting_dns_logs_v2"
    const val GLOBAL = "diting_global_v2"
}
