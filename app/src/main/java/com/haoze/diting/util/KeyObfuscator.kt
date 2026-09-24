package com.haoze.diting.util

/**
 * 轻量级 API 密钥混淆器。
 * 采用 3 组异或掩码与 Base64 编码，避免 API Key 在本地 SharedPreferences 中以纯明文形式直接暴露。
 */
object KeyObfuscator {
    private val ka = byteArrayOf(
        0x4D.toByte(), 0x1A.toByte(), 0xC8.toByte(), 0x37.toByte(),
        0x62.toByte(), 0x9E.toByte(), 0xFB.toByte(), 0x54.toByte()
    )
    private val kb = byteArrayOf(
        0x29.toByte(), 0x6C.toByte(), 0xD3.toByte(), 0x8E.toByte(),
        0x71.toByte(), 0x05.toByte(), 0xBA.toByte(), 0x4F.toByte()
    )
    private val kc = byteArrayOf(
        0xBE.toByte(), 0x34.toByte(), 0x65.toByte(), 0x8A.toByte(),
        0x71.toByte(), 0x22.toByte(), 0xD9.toByte(), 0x46.toByte()
    )

    fun seal(plain: String): String {
        if (plain.isBlank()) return ""
        val mixed = ByteArray(plain.length) { i ->
            val b = plain[i].code.toByte()
            (b.toInt() xor ka[i % ka.size].toInt() xor kb[i % kb.size].toInt() xor kc[i % kc.size].toInt()).toByte()
        }
        return java.util.Base64.getEncoder().encodeToString(mixed)
    }

    fun open(sealed: String): String {
        if (sealed.isBlank()) return ""
        return try {
            val mixed = java.util.Base64.getDecoder().decode(sealed)
            ByteArray(mixed.size) { i ->
                (mixed[i].toInt() xor ka[i % ka.size].toInt() xor kb[i % kb.size].toInt() xor kc[i % kc.size].toInt()).toByte()
            }.decodeToString()
        } catch (_: Exception) {
            ""
        }
    }
}
