package com.haoze.diting.server

import java.util.concurrent.TimeUnit

data class RootProbeResult(val available: Boolean, val uid: Int, val message: String)

/// Root is detected by running `su -c id -u` with a hard timeout. A denied prompt, a missing
/// binary, or a slow shell all mean "not root"; none of them may block app startup.
object ServerRoot {
    fun probe(): RootProbeResult = runCatching {
        val process = ProcessBuilder("su", "-c", "id -u")
            .redirectErrorStream(true)
            .start()
        if (!process.waitFor(6, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            return RootProbeResult(false, -1, "Root 授权超时")
        }
        val output = process.inputStream.bufferedReader().readText().trim()
        val uid = output.lineSequence().lastOrNull()?.trim()?.toIntOrNull() ?: -1
        if (process.exitValue() == 0 && uid == 0) {
            RootProbeResult(true, uid, "")
        } else {
            RootProbeResult(false, uid, output.ifBlank { "未授予 Root 权限" })
        }
    }.getOrElse { RootProbeResult(false, -1, it.message ?: "Root 探测失败") }

    fun shellQuote(value: String): String = "'" + value.replace("'", "'\\''") + "'"
}
