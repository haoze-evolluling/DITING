package com.haoze.diting.vpn

import android.os.ParcelFileDescriptor
import android.util.Log
import com.haoze.diting.engine.Engine
import com.haoze.diting.engine.SocketProtector

/** 一次 TUN 热切换的结果。 */
internal sealed interface TunnelSwap {
    /** 已切到新接口；调用方负责关闭 [previous] 并更新策略状态。 */
    data class Switched(
        val tun: ParcelFileDescriptor,
        val previous: ParcelFileDescriptor?,
    ) : TunnelSwap

    /** 新接口没有建立成功，旧会话原样保留。 */
    data object Unchanged : TunnelSwap

    /** 新接口失败但旧会话已恢复；调用方只需续挂监护线程。 */
    data class Restored(val error: Throwable) : TunnelSwap

    /** 旧会话也无法恢复，调用方应停止隧道。 */
    data class Failed(val error: Throwable) : TunnelSwap
}

/**
 * 建立新 TUN 接口并把引擎会话切到新 fd，保留引擎统计。
 *
 * 系统文档保证新接口建立失败时旧接口不受影响；会话切换失败时这里会尝试用
 * 旧 fd 重启会话，调用方只需处理状态、监护线程与失败收尾。
 */
internal object TunnelSwitcher {
    fun swap(
        engine: Engine,
        protector: SocketProtector,
        previous: ParcelFileDescriptor?,
        logTag: String,
        establish: () -> ParcelFileDescriptor?,
    ): TunnelSwap {
        val newTun = establish() ?: return TunnelSwap.Unchanged
        val newFd = try {
            newTun.fd
        } catch (t: IllegalStateException) {
            runCatching { newTun.close() }
            Log.w(logTag, "tunnel swap skipped: ${t.message}")
            return TunnelSwap.Unchanged
        }
        val previousFd = previous?.let { runCatching { it.fd }.getOrNull() }
        try {
            engine.restartFull(newFd.toLong(), protector)
        } catch (t: Throwable) {
            runCatching { newTun.close() }
            if (engine.isFullRunning()) return TunnelSwap.Restored(t)
            if (previousFd == null) return TunnelSwap.Failed(t)
            val restored = runCatching {
                engine.restartFull(previousFd.toLong(), protector)
            }.isSuccess
            Log.w(logTag, "tunnel swap failed; kept the previous interface", t)
            return if (restored) TunnelSwap.Restored(t) else TunnelSwap.Failed(t)
        }
        return TunnelSwap.Switched(newTun, previous)
    }
}
