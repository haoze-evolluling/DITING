package com.haoze.diting.ui

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import com.haoze.diting.ui.components.AppConfirmDialog

enum class PermissionDisclosure {
    VPN
}

@Composable
fun InitialAgreementDialog(
    onAccept: () -> Unit,
    onDecline: () -> Unit
) {
    BackHandler(enabled = true, onBack = onDecline)
    AppConfirmDialog(
        onDismissRequest = onDecline,
        title = "使用须知",
        message = "软件说明\n" +
            "谛听是一款基于 Android 本地 VPN 的 DNS 管理工具。本软件旨在屏蔽、过滤有害域名，净化网络环境，并不用于过滤商业广告。\n\n" +
            "注意事项\n" +
            "软件依赖本地 VPN 与上游 DNS 运行，解析表现受网络环境与配置影响；规则与日志均保存在设备本机。启用扩展功能可能改变网络行为，请在了解其作用后谨慎使用。\n\n" +
            "免责条款\n" +
            "本软件按现状提供。使用者须遵守相关法律法规，自行确认规则与上游来源的合法性及安全性。严禁将本软件用于任何违法用途；对于滥用软件或将其用于其他用途所产生的后果，由使用者自行承担。",
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
    AppConfirmDialog(
        onDismissRequest = onDismiss,
        title = "VPN 连接权限",
        message = "谛听需要建立本地 VPN 来处理和过滤 DNS 请求。此权限用于在设备上接管 DNS流量，不会将全部网络流量发送到远程 VPN 服务器。",
        confirmLabel = "继续",
        cancelLabel = "暂不允许",
        onConfirm = onContinue
    )
}
