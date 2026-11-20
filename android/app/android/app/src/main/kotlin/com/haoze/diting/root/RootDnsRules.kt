package com.haoze.diting.root

import android.content.Context
import java.util.concurrent.TimeUnit

internal object RootDnsRules {
    private const val OUT_V4 = "DITING_ROOT_DNS"
    private const val IN_V4 = "DITING_ROOT_DNS_IN"
    private const val OUT_V6 = "DITING_ROOT_DNS6"
    private const val IN_V6 = "DITING_ROOT_DNS6_IN"

    private const val CLEANUP_TIMEOUT_SECONDS = 4L

    private const val TEARDOWN_MARKER = "__DITING_TEARDOWN_OK__"

    fun install(context: Context, port: Int, uid: Int): String? {
        if (port !in 1..65535) return "无效的 DNS 端口"
        val v4 = runRoot(installScript("iptables", OUT_V4, IN_V4, port, uid), 12)
        if (!v4.ok) return v4.message()
        val v6 = runRoot(installScript("ip6tables", OUT_V6, IN_V6, port, uid), 12)
        if (!v6.ok) {
            runRoot(removeScript("ip6tables", OUT_V6, IN_V6), 8)
            runRoot(installInputScript("ip6tables", IN_V6, port), 8)
        }
        return null
    }

    fun removeAll() {
        runRoot(removeScript("iptables", OUT_V4, IN_V4), 8)
        runRoot(removeScript("ip6tables", OUT_V6, IN_V6), 8)
    }

    fun disablePrivateDns(context: Context): Boolean {
        val current = readPrivateDnsMode() ?: return false
        if (current == "off") return false
        RootDnsRuntime.rememberPrivateDns(context, current)
        val result = runRoot("settings put global private_dns_mode off", 8)
        if (!result.ok) {
            RootDnsRuntime.clearPrivateDns(context)
            return false
        }
        return true
    }

    fun restorePrivateDns(context: Context) {
        val previous = RootDnsRuntime.previousPrivateDns(context) ?: return
        val result = runRoot(
            "settings put global private_dns_mode ${shellQuote(normalizePrivateDns(previous))}",
            8,
        )
        if (result.ok) RootDnsRuntime.clearPrivateDns(context)
    }

    fun teardown(context: Context): Boolean {
        val previous = RootDnsRuntime.previousPrivateDns(context)
        val commands = buildList {
            addAll(removeCommands("iptables", OUT_V4, IN_V4))
            addAll(removeCommands("ip6tables", OUT_V6, IN_V6))
            if (previous != null) {
                add(
                    "settings put global private_dns_mode " +
                        "${shellQuote(normalizePrivateDns(previous))} || exit 9",
                )
            }
            add("ndc resolver flushdefaultif >/dev/null 2>&1")
            add("cmd netd resolver flushdefaultif >/dev/null 2>&1")
            add("echo $TEARDOWN_MARKER")
        }
        val result = runRoot(commands.joinToString("; "), CLEANUP_TIMEOUT_SECONDS)
        val ok = result.exitCode == 0 && result.output.contains(TEARDOWN_MARKER)
        if (ok) RootDnsRuntime.clearPrivateDns(context)
        return ok
    }

    fun flushCaches() {
        runRoot(
            "ndc resolver flushdefaultif >/dev/null 2>&1" +
                "; cmd netd resolver flushdefaultif >/dev/null 2>&1" +
                "; ip -4 route flush cache >/dev/null 2>&1" +
                "; echo __DITING_OK__",
            8,
        )
    }

    private fun installScript(
        binary: String,
        outChain: String,
        inChain: String,
        port: Int,
        uid: Int,
    ): String = listOf(
        "command -v $binary >/dev/null 2>&1 || { echo __DITING_NO_BINARY__; exit 4; }",
        "$binary -t nat -N $outChain 2>/dev/null",
        "$binary -t nat -F $outChain 2>/dev/null || exit 5",
        "$binary -t nat -C OUTPUT -j $outChain 2>/dev/null || " +
            "$binary -t nat -I OUTPUT 1 -j $outChain || exit 6",
        "$binary -t nat -A $outChain -m owner --uid-owner $uid -j RETURN || exit 7",
        "$binary -t nat -A $outChain -p udp --dport 53 -j REDIRECT --to-ports $port || exit 8",
        "$binary -t nat -A $outChain -p tcp --dport 53 -j REDIRECT --to-ports $port || exit 9",
        "$binary -N $inChain 2>/dev/null",
        "$binary -F $inChain 2>/dev/null || exit 10",
        "$binary -C INPUT -j $inChain 2>/dev/null || $binary -I INPUT 1 -j $inChain || exit 11",
        "$binary -A $inChain -p udp --dport $port ! -i lo -j DROP || exit 12",
        "$binary -A $inChain -p tcp --dport $port ! -i lo -j DROP || exit 13",
        "echo __DITING_OK__",
    ).joinToString("; ")

    private fun installInputScript(binary: String, inChain: String, port: Int): String = listOf(
        "command -v $binary >/dev/null 2>&1 || { echo __DITING_NO_BINARY__; exit 4; }",
        "$binary -N $inChain 2>/dev/null",
        "$binary -F $inChain 2>/dev/null || exit 5",
        "$binary -C INPUT -j $inChain 2>/dev/null || $binary -I INPUT 1 -j $inChain || exit 6",
        "$binary -A $inChain -p udp --dport $port ! -i lo -j DROP || exit 7",
        "$binary -A $inChain -p tcp --dport $port ! -i lo -j DROP || exit 8",
        "echo __DITING_OK__",
    ).joinToString("; ")

    private fun removeScript(binary: String, outChain: String, inChain: String): String =
        (removeCommands(binary, outChain, inChain) + "echo __DITING_OK__")
            .joinToString("; ")

    private fun removeCommands(
        binary: String,
        outChain: String,
        inChain: String,
    ): List<String> = listOf(
        "$binary -t nat -D OUTPUT -j $outChain 2>/dev/null",
        "$binary -t nat -F $outChain 2>/dev/null",
        "$binary -t nat -X $outChain 2>/dev/null",
        "$binary -D INPUT -j $inChain 2>/dev/null",
        "$binary -F $inChain 2>/dev/null",
        "$binary -X $inChain 2>/dev/null",
    )

    private fun readPrivateDnsMode(): String? {
        val result = runRoot("settings get global private_dns_mode", 8)
        if (!result.ok) return null
        val value = result.output
            .lineSequence()
            .map(String::trim)
            .lastOrNull { it.isNotEmpty() && !it.startsWith("__DITING_") }
        return if (value == null || value == "null") "opportunistic" else value
    }

    private fun normalizePrivateDns(value: String): String = when (value) {
        "off", "opportunistic", "hostname" -> value
        else -> "opportunistic"
    }

    private fun shellQuote(value: String): String =
        "'" + value.replace("'", "'\\''") + "'"

    private fun runRoot(command: String, timeoutSeconds: Long): ShellResult = runCatching {
        val process = ProcessBuilder("su", "-c", "$command; echo __DITING_OK__")
            .redirectErrorStream(true)
            .start()
        if (!process.waitFor(timeoutSeconds, TimeUnit.SECONDS)) {
            process.destroyForcibly()
            return@runCatching ShellResult(124, "Root 命令超时")
        }
        ShellResult(process.exitValue(), process.inputStream.bufferedReader().readText().trim())
    }.getOrElse {
        ShellResult(-1, it.message ?: it.javaClass.simpleName)
    }

    private data class ShellResult(val exitCode: Int, val output: String) {
        val ok: Boolean
            get() = exitCode == 0 && output.contains("__DITING_OK__")

        fun message(): String {
            if (exitCode == 124) return output
            val detail = output.lineSequence().firstOrNull {
                it.isNotBlank() && !it.contains("__DITING_")
            }
            return detail ?: "Root 命令执行失败（$exitCode）"
        }
    }
}
