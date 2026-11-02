package com.haoze.diting.net

/// Runs a system binary (`ping` / `ping6`) and returns its combined output. The timeout
/// lives here because the bridge has no coroutine scope: a child that never closes
/// stdout would park a diagnostics worker thread forever. Null means no binary started.
internal object ProcessProbe {

    fun run(command: List<String>, capMs: Long): String? {
        val process = try {
            ProcessBuilder(command).redirectErrorStream(true).start()
        } catch (_: Exception) {
            return null
        }
        val output = StringBuilder()
        val reader = Thread({ drain(process, output) }, "diting-probe-reader").apply {
            isDaemon = true
            start()
        }
        return try {
            ProcessSupport.waitOrKill(process, capMs)
            // The reader can still be blocked in readLine after a kill; waiting
            // briefly beats returning a half-built string the parser reads as "no
            // replies".
            reader.join(READER_JOIN_MS)
            synchronized(output) { output.toString() }
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            runCatching { process.destroy() }
            synchronized(output) { output.toString() }
        } finally {
            runCatching { process.destroy() }
        }
    }

    /// Blank output counts as no answer, so a broken `ping6` falls through to `ping -6`.
    fun runFirst(candidates: List<List<String>>, capMs: Long): String? {
        for (command in candidates) {
            val output = run(command, capMs)
            if (!output.isNullOrBlank()) return output
        }
        return null
    }

    private fun drain(process: Process, output: StringBuilder) {
        runCatching {
            process.inputStream.bufferedReader().use { reader ->
                while (true) {
                    val line = reader.readLine() ?: break
                    synchronized(output) { output.appendLine(line) }
                }
            }
        }
    }

    private const val READER_JOIN_MS = 500L
}
