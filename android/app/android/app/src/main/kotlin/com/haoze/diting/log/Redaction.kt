package com.haoze.diting.log

/// Secret masking for runtime-event values, mirroring `runtime_event::redact` on the Rust side.
///
/// The native kernel already redacts, so this is defense-in-depth: it runs at the Kotlin boundary
/// too, which keeps the fallback writer (native library unavailable) from ever writing a
/// subscription URL or proxy password. Three shapes are masked: an `Authorization: Bearer` token,
/// URL userinfo (`scheme://user:pass@host`), and a sensitive `key=value` (token, password, sub, …).
internal object Redaction {
    private val bearer = Regex("(?i)\\b(Bearer)\\s+\\S+")
    private val userinfo = Regex("://[^/@\\s]+@")
    private val keyValue = Regex(
        "(?i)(?<![A-Za-z0-9_])" +
            "(token|access_token|refresh_token|password|passwd|pwd|secret|api_?key|" +
            "auth|authorization|subscribe|subscription|session|cookie|sig|signature)" +
            "=([^&;,\\s\"')\\]#]+)",
    )

    fun redact(input: String): String {
        if (input.isEmpty()) return input
        var out = bearer.replace(input) { match -> "${match.groupValues[1]} ***" }
        out = userinfo.replace(out, "://***@")
        out = keyValue.replace(out) { match -> "${match.groupValues[1]}=***" }
        return out
    }
}
