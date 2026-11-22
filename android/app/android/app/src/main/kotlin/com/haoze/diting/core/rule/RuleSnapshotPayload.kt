package com.haoze.diting.core.rule

import java.io.ByteArrayOutputStream

internal class RuleSnapshotInput(
    val filterEnabled: Boolean,
    val blockIndexUsable: Boolean,
    val importantBlockUsable: Boolean,
    val allowIndexUsable: Boolean,
    val importantAllowUsable: Boolean,
    val triePaths: List<String?>,
    val appAllowlist: Map<String, Set<String>>,
    val blockCustom: List<EnabledRule>,
    val blockSubscription: List<EnabledRule>,
    val allowCustom: List<EnabledRule>,
    val allowSubscription: List<EnabledRule>,
)

internal object RuleSnapshotPayload {
    private const val LAYOUT: Int = 1
    private const val NULL_TEXT: Int = -1

    fun encode(input: RuleSnapshotInput): ByteArray {
        val out = ByteArrayOutputStream(1 shl 16)
        out.write(LAYOUT)
        var flags = 0
        if (input.blockIndexUsable) flags = flags or 1
        if (input.importantBlockUsable) flags = flags or 2
        if (input.allowIndexUsable) flags = flags or 4
        if (input.importantAllowUsable) flags = flags or 8
        if (input.filterEnabled) flags = flags or 16
        out.write(flags)
        for (path in input.triePaths) writeOptionalText(out, path)
        writeInt(out, input.appAllowlist.size)
        for ((packageName, domains) in input.appAllowlist) {
            writeText(out, packageName)
            writeInt(out, domains.size)
            for (domain in domains) writeText(out, domain)
        }
        writeRows(out, input.blockCustom)
        writeRows(out, input.blockSubscription)
        writeRows(out, input.allowCustom)
        writeRows(out, input.allowSubscription)
        return out.toByteArray()
    }

    private fun writeRows(out: ByteArrayOutputStream, rows: List<EnabledRule>) {
        writeInt(out, rows.size)
        for (row in rows) writeRow(out, row)
    }

    private fun writeRow(out: ByteArrayOutputStream, row: EnabledRule) {
        writeText(out, row.pattern)
        writeText(out, row.source)
        var flags = 0
        if (row.important) flags = flags or 1
        if (row.appInverted) flags = flags or 2
        if (row.isWildcard) flags = flags or 4
        if (row.isRegex) flags = flags or 8
        out.write(flags)
        writeOptionalText(out, row.appScope)
        writeOptionalText(out, row.denyallow)
        writeOptionalText(out, row.dnsType)
    }

    private fun writeText(out: ByteArrayOutputStream, value: String) {
        val bytes = value.toByteArray(Charsets.UTF_8)
        writeInt(out, bytes.size)
        out.write(bytes)
    }

    private fun writeOptionalText(out: ByteArrayOutputStream, value: String?) {
        if (value == null) {
            writeInt(out, NULL_TEXT)
        } else {
            writeText(out, value)
        }
    }

    private fun writeInt(out: ByteArrayOutputStream, value: Int) {
        out.write(value and 0xFF)
        out.write((value ushr 8) and 0xFF)
        out.write((value ushr 16) and 0xFF)
        out.write((value ushr 24) and 0xFF)
    }
}
