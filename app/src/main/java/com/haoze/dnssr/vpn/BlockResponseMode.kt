package com.haoze.dnssr.vpn

enum class BlockResponseMode(
    val storageValue: String,
    val displayName: String
) {
    NXDOMAIN("nxdomain", "域名不存在（NXDOMAIN）"),
    NODATA("nodata", "域名存在但无记录（NODATA）"),
    REFUSED("refused", "拒绝查询（REFUSED）"),
    ZERO_ADDRESS("zero_address", "返回零地址");

    companion object {
        fun fromStorageValue(value: String?): BlockResponseMode {
            return values().firstOrNull { it.storageValue == value } ?: NXDOMAIN
        }
    }
}
