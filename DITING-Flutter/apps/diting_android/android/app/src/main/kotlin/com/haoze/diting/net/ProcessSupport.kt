package com.haoze.diting.net

/// API-24-safe process control for the ping probes. `waitFor(timeout)`, `isAlive()`
/// and `destroyForcibly()` are all API 26 while minSdk is 24, so the poll loop uses
/// `exitValue()` + `destroy()`, which exist on every API level.
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

    /// `exitValue()` throws while the child is alive; that is the only liveness probe API 24 has
    fun isRunning(process: Process): Boolean = try {
        process.exitValue()
        false
    } catch (_: IllegalThreadStateException) {
        true
    } catch (_: Exception) {
        // A silent exit code means it is gone; treating it as alive would spin to the deadline.
        false
    }

    private const val POLL_INTERVAL_MS = 40L
}
