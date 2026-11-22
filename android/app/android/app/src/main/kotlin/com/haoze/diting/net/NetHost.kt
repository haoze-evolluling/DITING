package com.haoze.diting.net

internal object NetHost {

    fun sanitize(input: String): String = ProbeNative.sanitizeHost(input)
}
