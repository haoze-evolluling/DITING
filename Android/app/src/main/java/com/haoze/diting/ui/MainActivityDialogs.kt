package com.haoze.diting.ui

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import com.haoze.diting.ui.components.AppConfirmDialog

enum class PermissionDisclosure {
    VPN,
    NOTIFICATION,
    BATTERY_OPTIMIZATION
}

@Composable
fun InitialAgreementDialog(
    onAccept: () -> Unit,
    onDecline: () -> Unit
) {
    BackHandler(enabled = true, onBack = onDecline)
    AppConfirmDialog(
        onDismissRequest = onDecline,
        title = "使用须知与免责声明",
        message = "软件说明\n" +
            "谛听是一款专注于本地 DNS 解析优化与网络规则过滤的开源工具。提供三种工作模式：普通模式（全隧道深度管控）、极速模式（纯 Kotlin 原生轻量窄路由）与独立服务器模式（局域网免 VPN 服务）。本软件完全在设备本地闭环运行，无任何远程数据上传与隐私追踪。\n\n" +
            "运行机制与注意事项\n" +
            "普通模式与极速模式依赖 Android 本地 VPN 接口接管 DNS 解析，不连接任何远程 VPN 服务器；独立服务器模式无需 VPN 权限，直接监听本地 1053 端口供局域网设备接入。规则与日志完整保存在本机，启用高级扩展功能前请了解其具体影响。\n\n" +
            "免责条款\n" +
            "本软件按现状提供。使用者须遵守相关法律法规，自行确认规则与上游解析来源的合法性及安全性。严禁将本软件用于任何违法用途；使用者因自行配置或使用本软件所产生的后果由使用者自行承担。",
        confirmLabel = "同意并继续",
        cancelLabel = "不同意并退出",
        onConfirm = onAccept
    )
}

@Composable
fun PermissionDisclosureDialog(
    disclosure: PermissionDisclosure,
    onContinue: () -> Unit,
    onDismiss: () -> Unit
) {
    val (title, message) = when (disclosure) {
        PermissionDisclosure.VPN -> "VPN 连接权限" to
            "谛听需要建立本地 VPN 虚拟通道来捕获和优化 DNS 请求。此权限仅用于在设备本地处理 DNS 流量，不会将您的网络数据上传至任何远程 VPN 服务器。"
        PermissionDisclosure.NOTIFICATION -> "通知展示权限" to
            "谛听需要显示前台服务通知以维持后台解析守护进程稳定存活，并在通知栏提供实时状态与快捷控制。未授权可能导致服务被系统异常终止。"
        PermissionDisclosure.BATTERY_OPTIMIZATION -> "忽略电池优化" to
            "为了保障解析服务在设备锁屏或息屏后依然稳定可用，建议允许谛听在后台运行并忽略系统激进的电池优化。"
    }

    AppConfirmDialog(
        onDismissRequest = onDismiss,
        title = title,
        message = message,
        confirmLabel = "继续",
        cancelLabel = "暂不允许",
        onConfirm = onContinue
    )
}
