package com.haoze.diting.crash

import java.nio.charset.StandardCharsets

/**
 * Text recovery and plain-text tombstone sanitizing routines.
 */
internal object TombstoneTextSanitizer {

    fun sanitizePlainTextTombstone(bytes: ByteArray): String {
        val text = String(bytes, StandardCharsets.UTF_8)
        val lines = text.lineSequence().take(200).toList()
        val sb = StringBuilder(text.length.coerceAtMost(8192))
        for (line in lines) {
            // Drop the huge, useless "memory map:" / "memory near " blocks so
            // the output does not balloon
            if (line.startsWith("memory map:") || line.startsWith("memory near ")) {
                sb.append("\n...(Excessive memory dumps truncated)...\n")
                break
            }
            sb.append(line).append("\n")
        }
        return sb.toString()
    }

    fun fallbackExtractText(bytes: ByteArray): String {
        val sb = StringBuilder()
        sb.append("*** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***\n")
        sb.append("(Binary Protobuf Tombstone - Parsed with Text Recovery)\n\n")

        // Extract every meaningful run of ASCII/UTF-8 text in the buffer
        var i = 0
        while (i < bytes.size) {
            val start = i
            while (i < bytes.size && (bytes[i] in 32..126 || bytes[i] == '\n'.code.toByte())) {
                i++
            }
            val len = i - start
            if (len >= 6) {
                val s = String(bytes, start, len, StandardCharsets.UTF_8).trim()
                if (s.isNotBlank() && !s.contains("????")) {
                    if (s.contains("Build fingerprint") || s.contains("SIGABRT") || s.contains("SIGSEGV") ||
                        s.contains("FORTIFY") || s.contains("prevented") || s.contains("Exception") ||
                        s.contains("OutOfMemory") || s.contains(".so") || s.contains("#0") || s.startsWith(">>>")
                    ) {
                        sb.append(s).append("\n")
                    }
                }
            }
            i++
        }
        return sb.toString()
    }
}
