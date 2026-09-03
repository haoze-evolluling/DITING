package com.haoze.dnssr.vpn

import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object SubscriptionUpdateCoordinator {
    private val mutex = Mutex()
    private val pendingManualUpdates = AtomicInteger(0)

    suspend fun <T> runManual(block: suspend () -> T): T {
        pendingManualUpdates.incrementAndGet()
        return try {
            mutex.withLock { block() }
        } finally {
            pendingManualUpdates.decrementAndGet()
        }
    }

    suspend fun runAutomatic(block: suspend (shouldStop: () -> Boolean) -> Unit): Boolean {
        if (pendingManualUpdates.get() > 0 || !mutex.tryLock()) return false
        return try {
            if (pendingManualUpdates.get() > 0) return false
            block { pendingManualUpdates.get() > 0 }
            true
        } finally {
            mutex.unlock()
        }
    }
}
