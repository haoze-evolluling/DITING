package com.haoze.diting.watchdog

import java.io.ByteArrayInputStream
import java.io.DataInputStream

internal enum class VpnWatchdogEvent(val code: Int) {
    NONE(0),
    OCCUPIED(1),
    RELEASED(2),
    USER_DISCONNECT(3);

    companion object {
        fun from(code: Int): VpnWatchdogEvent =
            entries.firstOrNull { it.code == code }
                ?: throw IllegalStateException("unknown VPN watchdog event $code")
    }
}

internal data class VpnWatchdogStep(
    val event: VpnWatchdogEvent,
    val nextDelayMs: Long,
)

internal enum class VpnReconnectAction {
    RECONNECT,
    USER_DISCONNECT,
    NEEDS_CONSENT,
    GIVE_UP;

    companion object {
        fun from(code: Int): VpnReconnectAction = when (code) {
            0 -> RECONNECT
            1 -> USER_DISCONNECT
            2 -> NEEDS_CONSENT
            3 -> GIVE_UP
            else -> throw IllegalStateException("unknown VPN reconnect action $code")
        }
    }
}

/// Native VPN-slot watchdog (`rust/diting-vpn-config-core/src/watchdog.rs`).
///
/// Kotlin still owns the Handler timers, the ConnectivityManager callback, the notification and
/// `VpnService.prepare`; the confirmation window, occupied/released phases, debounce and reconnect
/// decision come from here. The library is required: a revoke on a build without it throws instead
/// of following a second state machine.
internal class VpnWatchdogNative private constructor() {
    external fun newHandle(): Long
    external fun free(handle: Long)
    external fun start(handle: Long, nowMs: Long): Long
    external fun evaluate(handle: Long, nowMs: Long, occupied: Boolean): ByteArray?
    external fun stop(handle: Long)
    external fun shouldFollow(
        enabled: Boolean,
        currentMode: String,
        expectedMode: String,
        hasIntent: Boolean,
    ): Boolean
    external fun reclaimAllowed(enabled: Boolean, currentMode: String, expectedMode: String): Boolean
    external fun reconnectDecision(
        enabled: Boolean,
        currentMode: String,
        expectedMode: String,
        consentMissing: Boolean,
        hasIntent: Boolean,
    ): Int

    companion object {
        private val instance: VpnWatchdogNative by lazy {
            try {
                System.loadLibrary("diting_kernels")
                VpnWatchdogNative()
            } catch (error: Throwable) {
                throw IllegalStateException(
                    "native VPN watchdog kernel unavailable; build it with " +
                        "`python rust/build_android.py`",
                    error,
                )
            }
        }

        fun newHandle(): Long {
            val handle = instance.newHandle()
            check(handle != 0L) { "native VPN watchdog returned a null handle" }
            return handle
        }

        fun free(handle: Long) = instance.free(handle)

        /// Starts a new confirmation window and returns the first poll delay.
        fun start(handle: Long, nowMs: Long): Long {
            val delay = instance.start(handle, nowMs)
            check(delay >= 0L) { "native VPN watchdog rejected the handle" }
            return delay
        }

        /// One poll; the returned delay is what the caller should schedule next.
        fun evaluate(handle: Long, nowMs: Long, occupied: Boolean): VpnWatchdogStep {
            val bytes = requireNotNull(instance.evaluate(handle, nowMs, occupied)) {
                "native VPN watchdog rejected the poll"
            }
            DataInputStream(ByteArrayInputStream(bytes)).use { input ->
                val event = VpnWatchdogEvent.from(input.readUnsignedByte())
                return VpnWatchdogStep(event, input.readLong())
            }
        }

        fun stop(handle: Long) = instance.stop(handle)

        fun shouldFollow(
            enabled: Boolean,
            currentMode: String,
            expectedMode: String,
            hasIntent: Boolean,
        ): Boolean = instance.shouldFollow(enabled, currentMode, expectedMode, hasIntent)

        fun reclaimAllowed(
            enabled: Boolean,
            currentMode: String,
            expectedMode: String,
        ): Boolean = instance.reclaimAllowed(enabled, currentMode, expectedMode)

        fun reconnectDecision(
            enabled: Boolean,
            currentMode: String,
            expectedMode: String,
            consentMissing: Boolean,
            hasIntent: Boolean,
        ): VpnReconnectAction = VpnReconnectAction.from(
            instance.reconnectDecision(
                enabled,
                currentMode,
                expectedMode,
                consentMissing,
                hasIntent,
            ),
        )
    }
}
