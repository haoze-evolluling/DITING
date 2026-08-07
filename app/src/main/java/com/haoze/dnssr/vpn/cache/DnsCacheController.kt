package com.haoze.dnssr.vpn.cache

import com.haoze.dnssr.data.dao.DnsCacheDao
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object DnsCacheController {
    private val mutex = Mutex()
    private var activeCache: DnsResponseCache? = null

    suspend fun register(cache: DnsResponseCache) {
        mutex.withLock { activeCache = cache }
    }

    suspend fun unregister(cache: DnsResponseCache) {
        mutex.withLock {
            if (activeCache === cache) activeCache = null
        }
    }

    suspend fun clearAll(dao: DnsCacheDao) {
        mutex.withLock { activeCache }?.clearMemory()
        dao.clearAll()
    }
}
