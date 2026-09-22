package com.haoze.diting.crash

import java.util.Locale

/**
 * Formats structured [ParsedTombstone] crash contexts into readable diagnostics reports.
 */
internal object TombstoneReportFormatter {

    fun format(tombstone: ParsedTombstone): String {
        val sb = StringBuilder(2048)
        sb.append("*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***\n")
        if (tombstone.buildFingerprint.isNotBlank()) sb.append("Build fingerprint: '${tombstone.buildFingerprint}'\n")
        if (tombstone.revision.isNotBlank()) sb.append("Revision: '${tombstone.revision}'\n")
        sb.append("ABI: '${tombstone.arch}'\n")
        if (tombstone.timestamp.isNotBlank()) sb.append("Timestamp: ${tombstone.timestamp}\n")
        sb.append(String.format(Locale.US, "Process: %s (PID: %d, TID: %d, UID: %d)\n",
            if (tombstone.processName.isBlank()) "unknown" else tombstone.processName,
            tombstone.pid, tombstone.tid, tombstone.uid))
        if (tombstone.selinuxLabel.isNotBlank()) sb.append("SELinux: ${tombstone.selinuxLabel}\n")

        if (tombstone.signalName.isNotBlank() || tombstone.signalNumber > 0) {
            val codeStr = if (tombstone.signalCodeName.isNotBlank()) tombstone.signalCodeName else "code ${tombstone.signalCode}"
            sb.append(String.format(Locale.US, "Signal: %d (%s), %s", tombstone.signalNumber, tombstone.signalName, codeStr))
            if (tombstone.hasFaultAddress) {
                sb.append(String.format(Locale.US, ", fault addr 0x%x", tombstone.faultAddress))
            }
            sb.append("\n")
        }

        if (tombstone.abortMessage.isNotBlank()) {
            sb.append("\nAbort Message: '${tombstone.abortMessage}'\n")
        }

        if (tombstone.causes.isNotEmpty()) {
            for (cause in tombstone.causes) {
                sb.append("Cause: $cause\n")
            }
        }

        // Locate the crashing thread first (TID match, or the first
        // thread that has frames)
        var crashingThread = tombstone.threads[tombstone.tid]
        if (crashingThread == null || crashingThread.frames.isEmpty()) {
            crashingThread = tombstone.threads.values.firstOrNull { it.frames.isNotEmpty() } ?: crashingThread ?: tombstone.threads.values.firstOrNull()
        }

        if (crashingThread != null) {
            val threadName = if (crashingThread.name.isNotBlank()) " (${crashingThread.name})" else ""
            sb.append("\nCrashing Thread: ${if (crashingThread.tid > 0) crashingThread.tid else tombstone.tid}$threadName\n")
            sb.append("Backtrace:\n")
            if (crashingThread.frames.isEmpty()) {
                sb.append("  (No symbolic stack frames available)\n")
            } else {
                crashingThread.frames.forEachIndexed { idx, frame ->
                    sb.append(frame.format(idx)).append("\n")
                }
            }

            if (crashingThread.registers.isNotEmpty()) {
                sb.append("\nRegisters:\n")
                var count = 0
                for ((reg, value) in crashingThread.registers) {
                    sb.append(String.format(Locale.US, "  %-4s %016x", reg, value))
                    count++
                    if (count % 4 == 0) sb.append("\n")
                }
                if (count % 4 != 0) sb.append("\n")
            }
        }

        // Summarize the remaining active threads (no full stacks, just key
        // info per thread, which keeps the report small)
        val otherThreads = tombstone.threads.values.filter { it != crashingThread && it.frames.isNotEmpty() }
        if (otherThreads.isNotEmpty()) {
            sb.append("\nOther Active Threads (${otherThreads.size}):\n")
            for (t in otherThreads.take(8)) {
                val topFrame = t.frames.firstOrNull()
                val topDesc = if (topFrame != null) {
                    val fn = if (topFrame.functionName.isNotBlank()) " in ${topFrame.functionName}" else ""
                    "${topFrame.fileName}$fn"
                } else "(idle)"
                sb.append(String.format(Locale.US, "  Thread %d \"%s\": %s\n", t.tid, t.name, topDesc))
            }
            if (otherThreads.size > 8) {
                sb.append(String.format(Locale.US, "  ... and %d more threads ...\n", otherThreads.size - 8))
            }
        }

        return sb.toString()
    }
}
