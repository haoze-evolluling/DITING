package com.haoze.diting.platform

import android.content.Context
import android.net.Uri
import java.io.File
import java.security.MessageDigest

/// Private copies of picked rule files, keyed by their `content://` address. Written only when
/// the SAF provider granted no persistable access, so a local subscription that would otherwise
/// become unreadable after a restart still has a readable source. Reads prefer the original URI
/// and fall back to this copy.
class RuleFileCache(context: Context) {

    private val dir = File(context.filesDir, "rules").apply { mkdirs() }

    fun write(uri: Uri, text: String) {
        runCatching {
            val target = fileFor(uri)
            val temp = File(target.parentFile, target.name + ".part")
            temp.writeText(text)
            if (target.exists()) target.delete()
            if (!temp.renameTo(target)) temp.delete()
        }
    }

    fun read(uri: Uri): String? = runCatching {
        val file = fileFor(uri)
        if (file.exists() && file.length() > 0) file.readText() else null
    }.getOrNull()

    fun delete(uri: Uri) {
        runCatching { fileFor(uri).delete() }
    }

    private fun fileFor(uri: Uri): File =
        File(dir, "rule_" + sha1(uri.toString()).take(24) + ".txt")

    private fun sha1(value: String): String =
        MessageDigest.getInstance("SHA-1").digest(value.toByteArray())
            .joinToString("") { "%02x".format(it) }
}
