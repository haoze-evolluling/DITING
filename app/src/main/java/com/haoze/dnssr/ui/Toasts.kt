package com.haoze.dnssr.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast

/** Shows a toast for [text] in the current app language, replacing the hand-written Toast.makeText + localizedText boilerplate. */
fun Context.showToast(text: String, duration: Int = Toast.LENGTH_SHORT) {
    Toast.makeText(this, localizedText(this, text), duration).show()
}

fun Context.copyToClipboard(label: String, text: String) {
    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

