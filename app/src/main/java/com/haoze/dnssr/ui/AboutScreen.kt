package com.haoze.dnssr.ui

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.haoze.dnssr.ui.components.SettingsScaffold
import com.haoze.dnssr.ui.components.SettingsCornerShape
import com.haoze.dnssr.ui.components.SettingsGroupTitle
import com.haoze.dnssr.ui.components.SettingsSectionSpacing
import com.haoze.dnssr.vpn.DnsVpnService
import kotlin.math.sqrt

private const val PROJECT_REPOSITORY_URL = "https://github.com/haoze-evolluling/DITING"

private data class AboutCapability(
    val title: String,
    val description: String
)

private val aboutCapabilities = listOf(
    AboutCapability("加密上游", "支持 DNS、DoH 与 DoT，并可管理自定义服务商。"),
    AboutCapability("规则与缓存", "以缓存、屏蔽规则、白名单和订阅规则减少重复请求与干扰。"),
    AboutCapability("可观测性", "通过请求日志、竞速统计、服务商健康和 Bootstrap 数据追踪状态。"),
    AboutCapability("独立引导", "支持 Bootstrap IP，降低解析加密上游域名时对系统 DNS 的依赖。"),
    AboutCapability("配置流转", "支持自定义服务、规则订阅的导入导出与自动更新。"),
    AboutCapability("快捷控制", "提供系统快捷设置磁贴，方便快速启停 DNS 本地通道。"),
    AboutCapability("应用管控", "按应用排除 VPN 或阻止联网，灵活控制每个应用的网络访问。"),
    AboutCapability("HTTPS 流量检查", "按应用检查 HTTP(S) 请求并应用域名和 URL 规则，需安装 HTTPS 检查根证书。")
)

private val aboutBoundaries = listOf(
    "默认仅处理 DNS" to "默认通过 Android VpnService 建立仅处理 DNS 的本地通道；启用 HTTPS 流量检查或禁止联网后，Go 隧道使用 Go 用户态网络栈接管 TCP、UDP、DNS 和 HTTP(S) 流量。",
    "实际解析表现" to "解析速度、稳定性和可用性取决于网络环境、所选上游和本机规则。",
    "隐私与本地存储" to "缓存、日志、规则与配置保存在设备本机。上游仍会收到必要查询；仅 DoH、DoT 加密到上游的 DNS 传输。"
)

@Composable
fun AboutScreen(
    onBack: () -> Unit,
    title: String = "应用信息"
) {
    val context = LocalContext.current
    val isServiceRunning = rememberDnsServiceRunning(context)
    val versionName = remember(context) {
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName.orEmpty()
        }.getOrDefault("")
    }
    val openRepository: () -> Unit = {
        runCatching {
            context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(PROJECT_REPOSITORY_URL)))
        }.onFailure {
            context.showToast("无法打开链接", Toast.LENGTH_SHORT)
        }
        Unit
    }

    SettingsScaffold(
        title = title,
        onBack = onBack,
        titleTrailing = {
            Box(
                modifier = Modifier
                    .padding(start = 8.dp)
                    .size(8.dp)
                    .background(
                        if (isServiceRunning) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                        CircleShape
                    )
            )
        }
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding),
            contentPadding = PaddingValues(
                start = 16.dp,
                top = 0.dp,
                end = 16.dp,
                bottom = 28.dp
            ),
            verticalArrangement = Arrangement.spacedBy(SettingsSectionSpacing)
        ) {
            item {
                AboutHero(versionName)
            }
            item {
                SettingsGroupTitle(localizedText("核心能力"))
            }
            item {
                CapabilityGrid()
            }
            item {
                SettingsGroupTitle(localizedText("运行边界"))
            }
            item {
                BoundaryGrid()
            }
            item {
                ProjectCard(onOpenRepository = openRepository)
            }
            item {
                Text(
                    text = localizedText("谛听 / RESOLUTION UNDER YOUR CONTROL"),
                    modifier = Modifier.fillMaxWidth(),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.labelMedium,
                    fontFamily = FontFamily.Monospace,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center
                )
            }
        }
    }
}

@Composable
private fun rememberDnsServiceRunning(context: Context): Boolean {
    var isRunning by remember(context) { mutableStateOf(DnsVpnService.isRunning(context)) }
    DisposableEffect(context) {
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(receiverContext: Context?, intent: Intent?) {
                if (intent?.action == DnsVpnService.ACTION_VPN_STATUS_CHANGED) {
                    isRunning = intent.getBooleanExtra(DnsVpnService.EXTRA_VPN_RUNNING, false)
                }
            }
        }
        ContextCompat.registerReceiver(
            context,
            receiver,
            IntentFilter(DnsVpnService.ACTION_VPN_STATUS_CHANGED),
            ContextCompat.RECEIVER_NOT_EXPORTED
        )
        onDispose { context.unregisterReceiver(receiver) }
    }
    return isRunning
}

@Composable
private fun AboutHero(versionName: String) {
    Card(
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.3f))
    ) {
        BoxWithConstraints(modifier = Modifier.padding(22.dp)) {
            val compact = maxWidth < 680.dp
            if (compact) {
                Column(verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    HeroCopy(versionName)
                    DnsPathDiagram()
                }
            } else {
                Row(horizontalArrangement = Arrangement.spacedBy(28.dp), verticalAlignment = Alignment.CenterVertically) {
                    HeroCopy(versionName, Modifier.weight(1f))
                    DnsPathDiagram(Modifier.widthIn(min = 300.dp, max = 360.dp).weight(0.65f))
                }
            }
        }
    }
}

@Composable
private fun HeroCopy(versionName: String, modifier: Modifier = Modifier) {
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            text = "// LOCAL DNS CONTROL PLANE",
            color = MaterialTheme.colorScheme.primary,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = localizedText("谛听 本地解析控制台"),
            color = MaterialTheme.colorScheme.onSurface,
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = localizedText("在 Android 设备本机管理 DNS 查询路径，让解析策略、缓存、规则与上游连接处于可控状态。"),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            style = MaterialTheme.typography.bodyLarge
        )
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            AboutBadge(localizedText("版本 ${versionName.ifBlank { "--" }}"))
            AboutBadge("Android VpnService")
            AboutBadge(localizedText("本地优先"))
        }
    }
}

@Composable
private fun AboutBadge(text: String) {
    Surface(
        shape = MaterialTheme.shapes.extraSmall,
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.65f),
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
    ) {
        Text(
            text = text,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 5.dp),
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.SemiBold,
            maxLines = 1
        )
    }
}

@Composable
private fun DnsPathDiagram(modifier: Modifier = Modifier) {
    val primary = MaterialTheme.colorScheme.primary
    val secondary = MaterialTheme.colorScheme.secondary
    val tertiary = MaterialTheme.colorScheme.tertiary
    val outline = MaterialTheme.colorScheme.outline
    val labelColor = MaterialTheme.colorScheme.onSurfaceVariant
    Card(
        modifier = modifier.fillMaxWidth().height(205.dp),
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.35f)),
        border = androidx.compose.foundation.BorderStroke(1.dp, outline.copy(alpha = 0.35f))
    ) {
        Canvas(modifier = Modifier.fillMaxWidth().height(205.dp).padding(horizontal = 14.dp, vertical = 12.dp)) {
            val radius = 20.dp.toPx()
            val device = androidx.compose.ui.geometry.Offset(size.width * 0.16f, size.height * 0.60f)
            val tunnel = androidx.compose.ui.geometry.Offset(size.width * 0.50f, size.height * 0.26f)
            val upstream = androidx.compose.ui.geometry.Offset(size.width * 0.82f, size.height * 0.67f)
            drawNodeConnection(device, tunnel, radius, outline)
            drawNodeConnection(tunnel, upstream, radius, secondary)
            listOf(device to primary, tunnel to tertiary, upstream to secondary).forEach { (center, color) ->
                drawCircle(color = color, radius = radius, center = center, style = Stroke(2.dp.toPx()))
                drawCircle(color = color, radius = 5.dp.toPx(), center = center)
            }
            val labelPaint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply {
                color = labelColor.toArgb()
                textSize = 10.sp.toPx()
                typeface = android.graphics.Typeface.create(android.graphics.Typeface.MONOSPACE, android.graphics.Typeface.BOLD)
                textAlign = android.graphics.Paint.Align.CENTER
            }
            drawContext.canvas.nativeCanvas.apply {
                drawText("DEVICE", device.x, device.y + radius + 18.dp.toPx(), labelPaint)
                drawText("DNS TUNNEL", tunnel.x, tunnel.y + radius + 18.dp.toPx(), labelPaint)
                drawText("UPSTREAM", upstream.x, upstream.y + radius + 18.dp.toPx(), labelPaint)
            }
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawNodeConnection(
    start: androidx.compose.ui.geometry.Offset,
    end: androidx.compose.ui.geometry.Offset,
    nodeRadius: Float,
    color: androidx.compose.ui.graphics.Color
) {
    val deltaX = end.x - start.x
    val deltaY = end.y - start.y
    val distance = sqrt(deltaX * deltaX + deltaY * deltaY)
    if (distance <= nodeRadius * 2) return
    val directionX = deltaX / distance
    val directionY = deltaY / distance
    drawLine(
        color = color,
        start = androidx.compose.ui.geometry.Offset(start.x + directionX * nodeRadius, start.y + directionY * nodeRadius),
        end = androidx.compose.ui.geometry.Offset(end.x - directionX * nodeRadius, end.y - directionY * nodeRadius),
        strokeWidth = 3.dp.toPx()
    )
}

@Composable
private fun CapabilityGrid() {
    BoxWithConstraints {
        val columns = if (maxWidth >= 680.dp) 3 else 2
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            aboutCapabilities.chunked(columns).forEachIndexed { rowIndex, row ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(IntrinsicSize.Max),
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    row.forEachIndexed { index, capability ->
                        CapabilityCard(capability, rowIndex * columns + index + 1, Modifier.weight(1f))
                    }
                    repeat(columns - row.size) { androidx.compose.foundation.layout.Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}

@Composable
private fun CapabilityCard(capability: AboutCapability, index: Int, modifier: Modifier) {
    Card(
        modifier = modifier.fillMaxHeight(),
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
    ) {
        Column(modifier = Modifier.padding(15.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("[%02d]".format(index), color = MaterialTheme.colorScheme.primary, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
            Text(localizedText(capability.title), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
            Text(localizedText(capability.description), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun BoundaryGrid() {
    BoxWithConstraints {
        val horizontal = maxWidth >= 680.dp
        if (horizontal) {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                aboutBoundaries.forEachIndexed { index, (title, description) ->
                    BoundaryCard(title, description, index, Modifier.weight(1f))
                }
            }
        } else {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                aboutBoundaries.forEachIndexed { index, (title, description) ->
                    BoundaryCard(title, description, index, Modifier.fillMaxWidth())
                }
            }
        }
    }
}

@Composable
private fun BoundaryCard(title: String, description: String, index: Int, modifier: Modifier) {
    val accents = listOf(MaterialTheme.colorScheme.primary, MaterialTheme.colorScheme.secondary, MaterialTheme.colorScheme.tertiary)
    Surface(
        modifier = modifier,
        shape = SettingsCornerShape,
        color = MaterialTheme.colorScheme.surface,
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
    ) {
        Column(modifier = Modifier.fillMaxWidth()) {
            HorizontalDivider(thickness = 2.dp, color = accents[index])
            Column(modifier = Modifier.padding(18.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(localizedText(title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                Text(localizedText(description), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
        }
    }
}

@Composable
private fun ProjectCard(onOpenRepository: () -> Unit) {
    Card(
        shape = SettingsCornerShape,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.35f))
    ) {
        Column(modifier = Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("MAINTAINED BY", color = MaterialTheme.colorScheme.primary, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold)
                Text("haoze-evolluling", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Text(localizedText("一位集美大学人工智能系大三学子"), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodyMedium)
            }
            Surface(
                modifier = Modifier.fillMaxWidth().clip(SettingsCornerShape).clickable(onClick = onOpenRepository),
                shape = SettingsCornerShape,
                color = MaterialTheme.colorScheme.primary.copy(alpha = 0.10f),
                border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.primary.copy(alpha = 0.38f))
            ) {
                Row(modifier = Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(localizedText("开源项目仓库"), style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                        Text(PROJECT_REPOSITORY_URL.removePrefix("https://"), color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Icon(Icons.AutoMirrored.Filled.OpenInNew, contentDescription = localizedText("打开项目仓库"), tint = MaterialTheme.colorScheme.primary)
                }
            }
        }
    }
}
