package com.haoze.diting.crash

import java.util.Locale

data class BacktraceFrame(
    val pc: Long = 0L,
    val functionName: String = "",
    val functionOffset: Long = 0L,
    val fileName: String = ""
) {
    fun format(index: Int): String {
        val f = if (fileName.isBlank()) "<unknown>" else fileName
        val fn = if (functionName.isBlank()) "" else " ($functionName${if (functionOffset > 0) "+$functionOffset" else ""})"
        return String.format(Locale.US, "  #%02d pc %016x  %s%s", index, pc, f, fn)
    }
}

data class ThreadInfo(
    val tid: Int = 0,
    val name: String = "",
    val frames: MutableList<BacktraceFrame> = mutableListOf(),
    val registers: MutableMap<String, Long> = linkedMapOf()
)

data class ParsedTombstone(
    var arch: String = "arm64",
    var buildFingerprint: String = "",
    var revision: String = "",
    var timestamp: String = "",
    var pid: Int = 0,
    var tid: Int = 0,
    var uid: Int = 0,
    var selinuxLabel: String = "",
    var processName: String = "",
    var signalNumber: Int = 0,
    var signalName: String = "",
    var signalCode: Int = 0,
    var signalCodeName: String = "",
    var faultAddress: Long = 0L,
    var hasFaultAddress: Boolean = false,
    var abortMessage: String = "",
    val causes: MutableList<String> = mutableListOf(),
    val threads: MutableMap<Int, ThreadInfo> = linkedMapOf()
) {
    fun format(): String = TombstoneReportFormatter.format(this)
}
