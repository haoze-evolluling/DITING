package com.haoze.diting.server

import android.content.Context
import android.util.Log
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * 用极小特权外壳把局域网 DNS 的 53 端口转到内核监听的本地端口。
 *
 * 内核始终以普通权限在 [INTERNAL_PORT] 监听，`su` 只负责执行一段安静的
 * `iptables` 规则脚本：入站 53 被 REDIRECT 到本地端口，源地址保持不变，所以
 * 查询日志里的客户端 IP 依然真实。脚本在前台阻塞读 stdin，App 进程退出后
 * stdin 关闭，规则随即自动删除，避免残留规则把局域网 DNS 指向死端口。
 */
object ServerPortRedirect {
    const val INTERNAL_PORT = 1053

    private const val TAG = "ServerPortRedirect"
    private const val SCRIPT_NAME = "server-port-redirect.sh"
    private const val READY = "READY"
    private const val TIMEOUT_MS = 12_000L

    @Volatile
    private var process: Process? = null

    @Volatile
    private var activePort = 0

    /** 返回 true 表示 53 → [port] 的重定向已生效。 */
    fun apply(context: Context, port: Int): Boolean {
        if (activePort == port && process?.isAlive == true) return true
        clear()
        val script = writeScript(context) ?: return false
        return runCatching {
            val started = ProcessBuilder(
                "su",
                "-c",
                "sh ${ServerRoot.shellQuote(script.absolutePath)} $port",
            ).redirectErrorStream(true).start()
            val answer = readFirstLine(started)
            if (answer?.trim() != READY) {
                Log.w(TAG, "53 端口重定向未启用: $answer")
                runCatching { started.destroy() }
                return false
            }
            process = started
            activePort = port
            true
        }.getOrElse {
            Log.w(TAG, "53 端口重定向执行失败", it)
            false
        }
    }

    /** 关闭脚本的标准输入，触发其 EXIT trap 删除规则。 */
    fun clear() {
        val current = process ?: return
        process = null
        activePort = 0
        runCatching {
            current.outputStream.close()
            if (!current.waitFor(3, TimeUnit.SECONDS)) current.destroy()
        }.onFailure { Log.w(TAG, "清理 53 端口重定向失败", it) }
    }

    private fun readFirstLine(started: Process): String? {
        val reader = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "diting-port-redirect").apply { isDaemon = true }
        }
        return try {
            reader.submit<String?> {
                started.inputStream.bufferedReader().readLine()
            }.get(TIMEOUT_MS, TimeUnit.MILLISECONDS)
        } catch (t: Throwable) {
            Log.w(TAG, "等待 53 端口重定向超时或失败", t)
            null
        } finally {
            reader.shutdownNow()
        }
    }

    private fun writeScript(context: Context): File? = runCatching {
        val file = File(context.filesDir, SCRIPT_NAME)
        if (!file.isFile || file.readText() != SCRIPT) {
            file.writeText(SCRIPT)
        }
        file
    }.getOrElse {
        Log.w(TAG, "写入 53 端口重定向脚本失败", it)
        null
    }

    private val SCRIPT = """
        #!/system/bin/sh
        PORT="${'$'}1"

        add_rule() {
            "${'$'}1" -t nat -C PREROUTING -p "${'$'}2" --dport 53 -j REDIRECT --to-ports "${'$'}PORT" 2>/dev/null ||
                "${'$'}1" -t nat -I PREROUTING -p "${'$'}2" --dport 53 -j REDIRECT --to-ports "${'$'}PORT" 2>/dev/null
        }

        del_rule() {
            while "${'$'}1" -t nat -C PREROUTING -p "${'$'}2" --dport 53 -j REDIRECT --to-ports "${'$'}PORT" 2>/dev/null; do
                "${'$'}1" -t nat -D PREROUTING -p "${'$'}2" --dport 53 -j REDIRECT --to-ports "${'$'}PORT" 2>/dev/null || break
            done
        }

        cleanup() {
            del_rule iptables udp
            del_rule iptables tcp
            del_rule ip6tables udp
            del_rule ip6tables tcp
        }
        trap cleanup EXIT INT TERM HUP

        if [ -z "${'$'}PORT" ]; then
            echo "NO_PORT"
            exit 2
        fi
        if ! command -v iptables >/dev/null 2>&1; then
            echo "NO_IPTABLES"
            exit 3
        fi

        add_rule iptables udp
        add_rule iptables tcp
        if command -v ip6tables >/dev/null 2>&1; then
            add_rule ip6tables udp
            add_rule ip6tables tcp
        fi

        iptables -t nat -C PREROUTING -p udp --dport 53 -j REDIRECT --to-ports "${'$'}PORT" 2>/dev/null || {
            echo "APPLY_FAILED"
            exit 4
        }

        echo READY

        # App 进程退出后 stdin 关闭，循环结束并执行 cleanup。
        while read -r _; do :; done
    """.trimIndent() + "\n"
}
