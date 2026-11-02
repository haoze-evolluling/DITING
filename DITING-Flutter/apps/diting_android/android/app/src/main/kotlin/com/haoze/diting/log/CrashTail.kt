package com.haoze.diting.log

/// Picks this app's crashes out of the system crash buffer.
///
/// The buffer is shared by every app on the device, so only blocks that name the package are kept:
/// an exported log never carries another app's stack trace.
internal object CrashTail {
    /// Lines that start a new entry in the buffer: logcat's own separators and debuggerd's tombstone
    /// banner.
    private fun startsBlock(line: String): Boolean =
        line.startsWith("--------- beginning of") || line.startsWith("*** *** ***")

    fun select(lines: List<String>, packageName: String): List<String> {
        if (lines.isEmpty()) return emptyList()
        val blocks = mutableListOf<MutableList<String>>()
        for (line in lines) {
            if (startsBlock(line) || blocks.isEmpty()) {
                blocks.add(mutableListOf(line))
            } else {
                blocks.last().add(line)
            }
        }
        return blocks.filter { block -> block.any { it.contains(packageName) } }.flatten()
    }
}
