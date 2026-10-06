package com.haoze.diting.server

import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.haoze.diting.AppLocalizedActivity
import com.haoze.diting.MainActivity
import com.haoze.diting.ui.mode.disableWindowTransitions

/**
 * Backward compatibility trampoline activity that forwards to MainActivity.
 * DNS mode is now embedded natively inside MainActivity as part of the Single-Activity architecture.
 */
class DnsMainActivity : AppLocalizedActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        disableWindowTransitions()
        val forwardIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            intent.extras?.let { putExtras(it) }
        }
        startActivity(forwardIntent)
        disableWindowTransitions()
        finish()
    }

    companion object {
        fun createIntent(context: Context): Intent {
            return Intent(context, MainActivity::class.java)
        }
    }
}
