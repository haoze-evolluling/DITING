package com.haoze.dnssr.vpn.cache

import com.haoze.dnssr.data.dao.DnsCacheDao
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object DnsCacheController {
    private val mutex = Mutex()
    private var activeCache: DnsResponseCache? = null
    private var onClearGoCache: (() -> Unit)? = null

    suspend fun register(cache: DnsResponseCache, clearGoCacheCallback: (() -> Unit)? = null) {
        mutex.withLock {
            activeCache = cache
            onClearGoCache = clearGoCacheCallback
        }
    }

    suspend fun unregister(cache: DnsResponseCache) {
        mutex.withLock {
            if (activeCache === cache) {
                activeCache = null
                onClearGoCache = null
            }
        }
    }

    suspend fun clearAll(dao: DnsCacheDao) {
        val (cache, clearGo) = mutex.withLock { activeCache to onClearGoCache }
        cache?.clearMemory()
        clearGo?.invoke()
        dao.clearAll()
    }
}
