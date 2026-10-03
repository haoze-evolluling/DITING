package com.haoze.diting.vpn

import android.content.Context
import android.util.Log
import com.haoze.diting.data.AppDatabase
import com.haoze.diting.data.dao.CosmeticRuleDao
import com.haoze.diting.data.entity.CosmeticRuleEntity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

/**
 * Manages cosmetic element-hiding rules and compiles them into CSS
 * for injection by the Go MITM engine.
 */
class CosmeticRuleManager(
    private val cosmeticRuleDao: CosmeticRuleDao
) {
    companion object {
        private const val TAG = "CosmeticRuleManager"

        @Volatile
        private var instance: CosmeticRuleManager? = null

        fun getInstance(context: Context): CosmeticRuleManager {
            return instance ?: synchronized(this) {
                instance ?: CosmeticRuleManager(
                    AppDatabase.getInstance(context.applicationContext).cosmeticRuleDao()
                ).also { instance = it }
            }
        }
    }

    /**
     * Compiles all active cosmetic rules to CSS.
     */
    suspend fun compileAllToCss(): String = withContext(Dispatchers.IO) {
        val rules = cosmeticRuleDao.enabledRules()
        if (rules.isEmpty()) return@withContext ""

        val sb = StringBuilder()
        val emitted = mutableSetOf<String>()

        for (rule in rules) {
            if (emitted.add(rule.selector)) {
                sb.append(rule.selector).append(" { display: none !important; }\n")
            }
        }

        sb.toString()
    }

    fun compileAllToCssBlocking(): String = runBlocking(Dispatchers.IO) {
        compileAllToCss()
    }
}
