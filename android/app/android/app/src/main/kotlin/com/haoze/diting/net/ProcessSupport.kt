package com.haoze.diting.net

internal object ProcessSupport {

    fun waitOrKill(process: Process, capMs: Long): Boolean {
        val deadline = System.nanoTime() + capMs * 1_000_000L
        while (System.nanoTime() < deadline) {
            if (!isRunning(process)) return true
            try {
                Thread.sleep(POLL_INTERVAL_MS)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
                break
            }
        }
        runCatching { process.destroy() }
        return false
    }

    fun isRunning(process: Process): Boolean = try {
        process.exitValue()
        false
    } catch (_: IllegalThreadStateException) {
        true
    } catch (_: Exception) {
        false
    }

    private const val POLL_INTERVAL_MS = 40L
}
