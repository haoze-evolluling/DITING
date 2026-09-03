package com.haoze.dnssr.ui

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.haoze.dnssr.ui.components.AppAlertDialog as AlertDialog
import com.haoze.dnssr.ui.components.SettingsGroup
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsInfoText
import com.haoze.dnssr.ui.components.SettingsItem
import com.haoze.dnssr.ui.components.SettingsNavigationGroup
import com.haoze.dnssr.ui.components.SettingsNavigationItemData
import com.haoze.dnssr.ui.components.SettingsTextItem
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsSurfaceGroup
import com.haoze.dnssr.vpn.GoInspectionCaManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun CaCertificateSettingsScreen(
    onBack: () -> Unit,
    onNavigateToGuide: () -> Unit
) {
    SettingsScaffold(title = localizedText("CA 证书设置"), onBack = onBack) { innerPadding ->
        Column(
            modifier = androidx.compose.ui.Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            CaCertificateManagement(onNavigateToGuide = onNavigateToGuide)
        }
    }
}

@Composable
fun CaCertificateManagement(onNavigateToGuide: () -> Unit) {
    val context = LocalContext.current
    var httpsReady by remember { mutableStateOf(AppSettings.isHttpsInspectionReady(context)) }
    var caFingerprint by remember { mutableStateOf<String?>(null) }
    var caBusy by remember { mutableStateOf(true) }
    var showInstallConfirmation by remember { mutableStateOf(false) }
    var showResetConfirmation by remember { mutableStateOf(false) }
    var showCaDetails by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun applyCertificateReadiness(ready: Boolean) {
        httpsReady = ready
        AppSettings.setHttpsInspectionReady(context, ready)
        if (!ready) {
            val wasEnabled = AppSettings.isHttpInspectionEnabled(context)
            AppSettings.setHttpInspectionEnabled(context, false)
            if (wasEnabled) RuntimeDnsSettingsRefresher.refreshAppExclusionsIfRunning(context)
        }
    }

    val securitySettingsLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) {
        scope.launch {
            val ready = withContext(Dispatchers.IO) {
                runCatching { GoInspectionCaManager.isInstalled(context) }.getOrDefault(false)
            }
            applyCertificateReadiness(ready)
            caBusy = false
            showInstallConfirmation = !ready
        }
    }

    LaunchedEffect(Unit) {
        val ready = withContext(Dispatchers.IO) {
            runCatching { GoInspectionCaManager.isInstalled(context) }.getOrDefault(false)
        }
        applyCertificateReadiness(ready)
        caBusy = false
        caFingerprint = withContext(Dispatchers.IO) {
            runCatching { GoInspectionCaManager.fingerprintSha256(context) }.getOrNull()
        }
    }

    fun exportCertificate(destinationUri: Uri) {
        caBusy = true
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching { GoInspectionCaManager.exportCertificateToUri(context, destinationUri) }
            }
            result.fold(
                onSuccess = {
                    Toast.makeText(context, localizedText(context, "CA 文件已保存，请在系统设置中手动安装"), Toast.LENGTH_LONG).show()
                    runCatching { securitySettingsLauncher.launch(Intent(Settings.ACTION_SECURITY_SETTINGS)) }
                        .onFailure {
                            caBusy = false
                            showInstallConfirmation = true
                        }
                },
                onFailure = { error ->
                    caBusy = false
                    Toast.makeText(
                        context,
                        localizedText(context, "导出根证书失败：${error.message ?: "未知错误"}"),
                        Toast.LENGTH_SHORT
                    ).show()
                }
            )
        }
    }
    val certificateExportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/x-x509-ca-cert")
    ) { uri ->
        if (uri != null) exportCertificate(uri) else caBusy = false
    }

    SettingsGroupTitle(localizedText("证书状态"))
    SettingsSurfaceGroup(content = listOf {
        SettingsItem(
            title = localizedText("根证书状态"),
            subtitle = localizedText(if (caBusy) "正在验证系统凭据…" else "用于目标应用的 HTTPS 流量解密")
        ) {
            Text(
                text = localizedText(if (httpsReady) "已验证" else "未验证"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    })
    SettingsInfoText(localizedText("仅已验证的根证书支持流量检查；启用了证书绑定（SSL Pinning）的应用将自动旁路。"))

    SettingsGroupTitle(localizedText("证书操作"))
    SettingsNavigationGroup(
        items = listOf(
            SettingsNavigationItemData(
                title = localizedText("安装与卸载指南"),
                subtitle = localizedText("查看各机型系统证书的安装、移除及安全说明"),
                onClick = onNavigateToGuide
            ),
            SettingsNavigationItemData(
                title = localizedText("安装根证书"),
                subtitle = localizedText("导出证书文件并前往系统设置安装"),
                value = localizedText(if (httpsReady) "已安装" else "未安装"),
                enabled = !caBusy,
                onClick = {
                    caBusy = true
                    certificateExportLauncher.launch(GoInspectionCaManager.EXPORTED_CERTIFICATE_NAME)
                }
            ),
            SettingsNavigationItemData(
                title = localizedText("证书指纹"),
                subtitle = localizedText("查看当前根证书的 SHA-256 指纹"),
                enabled = !caBusy,
                onClick = { showCaDetails = true }
            )
        )
    )

    SettingsGroupTitle(localizedText("证书管理"))
    SettingsSurfaceGroup(content = listOf {
        SettingsTextItem(
            title = localizedText("重新生成根证书"),
            subtitle = localizedText("作废当前私钥并生成新证书，重置后需重新安装"),
            enabled = !caBusy,
            textColor = MaterialTheme.colorScheme.error,
            onClick = { showResetConfirmation = true }
        )
    })

    if (showCaDetails) {
        AlertDialog(
            onDismissRequest = { showCaDetails = false },
            title = { Text(localizedText("CA 证书指纹")) },
            text = { Text(localizedText(caFingerprint?.let { "SHA-256 指纹：\n$it" } ?: "正在读取证书指纹…")) },
            confirmButton = { TextButton(onClick = { showCaDetails = false }) { Text(localizedText("关闭")) } }
        )
    }

    if (showInstallConfirmation) {
        AlertDialog(
            onDismissRequest = { showInstallConfirmation = false },
            title = { Text(localizedText("验证根证书")) },
            text = {
                Text(
                    localizedText("请在系统设置中选择“从存储设备安装 CA 证书”，并选择导出的 " +
                        GoInspectionCaManager.EXPORTED_CERTIFICATE_NAME +
                        " 文件。\n\n" +
                        "返回后谛听将自动验证安装状态。启用证书绑定（SSL Pinning）或自定义校验的应用将自动旁路转发。")
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    scope.launch {
                        val ready = withContext(Dispatchers.IO) {
                            runCatching { GoInspectionCaManager.isInstalled(context) }.getOrDefault(false)
                        }
                        applyCertificateReadiness(ready)
                        showInstallConfirmation = !ready
                    }
                }) { Text(localizedText("重新验证")) }
            },
            dismissButton = { TextButton(onClick = { showInstallConfirmation = false }) { Text(localizedText("稍后完成")) } }
        )
    }

    if (showResetConfirmation) {
        AlertDialog(
            onDismissRequest = { showResetConfirmation = false },
            title = { Text(localizedText("重新生成根证书")) },
            text = { Text(localizedText("重新生成将销毁当前 CA 私钥并生成全新证书。系统中已安装的旧证书需手动在系统设置中移除，新证书安装并验证后方可继续检查流量。")) },
            confirmButton = {
                TextButton(onClick = {
                    showResetConfirmation = false
                    caBusy = true
                    scope.launch {
                        val result = withContext(Dispatchers.IO) {
                            runCatching {
                                GoInspectionCaManager.reset(context)
                                GoInspectionCaManager.fingerprintSha256(context)
                            }
                        }
                        caBusy = false
                        result.onSuccess { fingerprint ->
                            caFingerprint = fingerprint
                            applyCertificateReadiness(false)
                        }
                        Toast.makeText(
                            context,
                            localizedText(context, if (result.isSuccess) "根证书已重新生成" else "重新生成根证书失败"),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }) { Text(localizedText("重新生成")) }
            },
            dismissButton = { TextButton(onClick = { showResetConfirmation = false }) { Text(localizedText("取消")) } }
        )
    }
}
