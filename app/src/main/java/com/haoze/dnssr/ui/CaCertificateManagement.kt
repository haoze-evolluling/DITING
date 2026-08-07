package com.haoze.dnssr.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
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
    SettingsScaffold(title = localizedText("CA证书设置"), onBack = onBack) { innerPadding ->
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
    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
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
                        localizedText(context, "导出 HTTPS 检查根证书失败：${error.message ?: "未知错误"}"),
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
            title = localizedText("HTTPS 检查根证书"),
            subtitle = localizedText(if (caBusy) "正在验证系统凭据库中的证书状态" else "用于所选应用的 HTTPS 流量检查")
        ) {
            Text(
                text = localizedText(if (httpsReady) "已验证" else "未验证"),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }
    })
    SettingsInfoText(localizedText("仅已安装并通过验证的根证书可用于 HTTPS 流量检查；部分应用可能因证书固定或自定义校验而不受支持。"))

    SettingsGroupTitle(localizedText("安装与查看"))
    SettingsNavigationGroup(
        items = listOf(
            SettingsNavigationItemData(
            title = localizedText("安装和卸载 HTTPS 检查根证书"),
            subtitle = localizedText("查看 Android 系统 CA 证书的安装、卸载和安全说明"),
            onClick = onNavigateToGuide
            ),
            SettingsNavigationItemData(
            title = localizedText("安装 HTTPS 检查根证书"),
            subtitle = localizedText("导出谛听 HTTPS 检查根证书，并前往系统设置完成安装"),
            value = localizedText(if (httpsReady) "已安装" else "未安装"),
            enabled = supported && !caBusy,
            onClick = {
                caBusy = true
                certificateExportLauncher.launch(GoInspectionCaManager.EXPORTED_CERTIFICATE_NAME)
            }
            ),
            SettingsNavigationItemData(
            title = localizedText("查看 HTTPS 检查根证书"),
            subtitle = localizedText("查看当前 HTTPS 检查根证书的 SHA-256 指纹"),
            enabled = supported && !caBusy,
            onClick = { showCaDetails = true }
            )
        )
    )

    SettingsGroupTitle(localizedText("证书管理"))
    SettingsSurfaceGroup(content = listOf {
        SettingsTextItem(
            title = localizedText("重置 HTTPS 检查根证书"),
            subtitle = localizedText("废止当前证书并生成新证书；之后需要重新安装"),
            enabled = supported && !caBusy,
            textColor = MaterialTheme.colorScheme.error,
            onClick = { showResetConfirmation = true }
        )
    })

    if (showCaDetails) {
        AlertDialog(
            onDismissRequest = { showCaDetails = false },
            title = { Text(localizedText("HTTPS 检查根证书")) },
            text = { Text(localizedText(caFingerprint?.let { "SHA-256 指纹：\n$it" } ?: "正在读取 HTTPS 检查根证书的 SHA-256 指纹…")) },
            confirmButton = { TextButton(onClick = { showCaDetails = false }) { Text(localizedText("关闭")) } }
        )
    }

    if (showInstallConfirmation) {
        AlertDialog(
            onDismissRequest = { showInstallConfirmation = false },
            title = { Text(localizedText("验证 HTTPS 检查根证书")) },
            text = {
                Text(
                    localizedText("请在系统设置中选择“从存储设备安装 CA 证书”，然后选择下载目录中的 " +
                        GoInspectionCaManager.EXPORTED_CERTIFICATE_NAME +
                        "。返回后谛听会通过系统 CA 存储按 SHA-256 指纹验证安装状态；若系统限制读取证书库，状态会保持未验证。\n\n" +
                        "安装成功只表示证书已进入系统用户凭据库，不代表所有应用都会信任它。证书固定、自定义校验、双向 TLS 等不兼容连接会由 HTTPS 流量检查自动旁路，并记录为“HTTPS 检查自动旁路”。")
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
            dismissButton = { TextButton(onClick = { showInstallConfirmation = false }) { Text(localizedText("尚未完成")) } }
        )
    }

    if (showResetConfirmation) {
        AlertDialog(
            onDismissRequest = { showResetConfirmation = false },
            title = { Text(localizedText("重置 HTTPS 检查根证书")) },
            text = { Text(localizedText("重置会删除当前 HTTPS 检查私有 CA 并生成新的私钥和根证书。系统中已安装的旧证书不会自动删除，请到系统凭据设置中手动移除；新证书重新安装并验证后，兼容应用才能继续进行 HTTPS 流量检查。")) },
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
                            localizedText(context, if (result.isSuccess) "HTTPS 检查根证书已重置" else "重置 HTTPS 检查根证书失败"),
                            Toast.LENGTH_SHORT
                        ).show()
                    }
                }) { Text(localizedText("立即重置")) }
            },
            dismissButton = { TextButton(onClick = { showResetConfirmation = false }) { Text(localizedText("取消")) } }
        )
    }
}
