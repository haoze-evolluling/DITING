package com.haoze.diting

import android.content.Context
import com.haoze.diting.automation.AutomationContract
import com.haoze.diting.automation.StateBroadcaster
import com.haoze.diting.control.BlockPauseLink
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class BlockPauseBridge(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "state" -> result.success(state())
            "pause" -> {
                val minutes = (call.argument<Any>("minutes") as? Number)?.toLong()
                    ?: AutomationContract.DEFAULT_PAUSE_MINUTES.toLong()
                val until = System.currentTimeMillis() + minutes.coerceAtLeast(0L) * 60_000L
                setPausedUntil(until)
                result.success(state())
            }
            "clear" -> {
                setPausedUntil(0L)
                result.success(state())
            }
            "setAllowlistOnly" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                BlockPauseLink.prefs(context).edit()
                    .putBoolean(AutomationContract.KEY_ALLOWLIST_ONLY, enabled).apply()
                BlockPauseLink.apply(context)
                StateBroadcaster.broadcast(context)
                result.success(state())
            }
            else -> result.notImplemented()
        }
    }

    private fun setPausedUntil(untilMs: Long) {
        BlockPauseLink.prefs(context).edit()
            .putLong(AutomationContract.KEY_PAUSED_UNTIL_MS, untilMs).apply()
        BlockPauseLink.apply(context)
        StateBroadcaster.broadcast(context)
    }

    private fun state(): Map<String, Any?> {
        val prefs = BlockPauseLink.prefs(context)
        return mapOf(
            "pausedUntilMs" to prefs.getLong(AutomationContract.KEY_PAUSED_UNTIL_MS, 0L),
            "allowlistOnly" to prefs.getBoolean(AutomationContract.KEY_ALLOWLIST_ONLY, false),
        )
    }

    companion object {
        const val CHANNEL = "com.haoze.diting/block_pause"
    }
}
