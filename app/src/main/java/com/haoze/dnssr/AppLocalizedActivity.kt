package com.haoze.dnssr

import android.content.Context
import androidx.activity.ComponentActivity
import com.haoze.dnssr.ui.AppLanguageManager

abstract class AppLocalizedActivity : ComponentActivity() {
    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppLanguageManager.wrap(newBase))
    }
}
