package com.haoze.dnssr.crash

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import androidx.core.content.pm.PackageInfoCompat
import com.haoze.dnssr.BuildConfig
import com.haoze.dnssr.vpn.DnsVpnService
import java.io.BufferedReader
import java.io.InputStreamReader
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.TimeUnit

/**
 * 负责在崩溃发生时全方位采集诊断信息。
 * 覆盖异常堆栈、崩溃线程、全线程快照、设备与系统参数、资源使用（内存/存储/电池/网络）、运行状态、崩溃前面包屑与 logcat。
 */
object CrashCollector {

    var appStartTimeMillis: Long = System.currentTimeMillis()
    var appStartElapsedRealtime: Long = SystemClock.elapsedRealtime()

    fun collectReport(
        context: Context,
        thread: Thread,
        throwable: Throwable,
        topActivityName: String?,
        isForeground: Boolean
    ): String {
        val now = System.currentTimeMillis()
        val localFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault())
        val utcFormat = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS 'UTC'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

        val sb = StringBuilder(8192)
        sb.append("================================================================================\n")
        sb.append("                           DNSSR CRASH REPORT\n")
        sb.append("================================================================================\n\n")

        sb.append("Timestamp (Local): ").append(localFormat.format(Date(now))).append("\n")
        sb.append("Timestamp (UTC)  : ").append(utcFormat.format(Date(now))).append("\n")
        sb.append("Epoch Millis     : ").append(now).append("\n\n")

        // 1. App Info
        appendSection(sb, "APPLICATION INFORMATION") {
            val pm = context.packageManager
            val packageInfo: PackageInfo? = runCatching { pm.getPackageInfo(context.packageName, 0) }.getOrNull()
            val appName = runCatching { context.applicationInfo.loadLabel(pm).toString() }.getOrDefault("DNSSR")
            val versionCode = packageInfo?.let { PackageInfoCompat.getLongVersionCode(it) } ?: -1L
            val versionName = packageInfo?.versionName ?: "Unknown"

            append("App Name         : ").append(appName).append("\n")
            append("Package Name     : ").append(context.packageName).append("\n")
            append("Version Name     : ").append(versionName).append("\n")
            append("Version Code     : ").append(versionCode).append("\n")
            append("Build Type       : ").append(if (BuildConfig.DEBUG) "DEBUG" else "RELEASE").append("\n")
            append("Target SDK       : ").append(context.applicationInfo.targetSdkVersion).append("\n")
            append("Min SDK          : ").append(context.applicationInfo.minSdkVersion).append("\n")
            append("Process Name     : ").append(getProcessName(context)).append("\n")
            append("Process ID (PID) : ").append(Process.myPid()).append("\n")
            append("User ID (UID)    : ").append(Process.myUid()).append("\n")
            append("App Uptime       : ").append(formatDuration(SystemClock.elapsedRealtime() - appStartElapsedRealtime)).append("\n")
            append("App Lifecycle    : ").append(if (isForeground) "Foreground" else "Background").append("\n")
            append("Top Activity     : ").append(topActivityName ?: "(None)").append("\n")
            val vpnRunning = runCatching { DnsVpnService.isRunning(context) }.getOrDefault(false)
            append("VPN Active       : ").append(vpnRunning).append("\n")
        }

        // 2. Device & OS Info
        appendSection(sb, "DEVICE & OPERATING SYSTEM") {
            append("Manufacturer     : ").append(Build.MANUFACTURER).append("\n")
            append("Brand            : ").append(Build.BRAND).append("\n")
            append("Model            : ").append(Build.MODEL).append("\n")
            append("Product          : ").append(Build.PRODUCT).append("\n")
            append("Device           : ").append(Build.DEVICE).append("\n")
            append("Board            : ").append(Build.BOARD).append("\n")
            append("Hardware         : ").append(Build.HARDWARE).append("\n")
            append("Android Version  : ").append(Build.VERSION.RELEASE)
                .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n")
            append("Security Patch   : ").append(Build.VERSION.SECURITY_PATCH).append("\n")
            append("Supported ABIs   : ").append(Build.SUPPORTED_ABIS.joinToString(", ")).append("\n")
            append("Fingerprint      : ").append(Build.FINGERPRINT).append("\n")
        }

        // 3. System & Runtime Status
        appendSection(sb, "RUNTIME & RESOURCE STATUS") {
            // JVM Memory
            val runtime = Runtime.getRuntime()
            val maxMem = runtime.maxMemory()
            val totalMem = runtime.totalMemory()
            val freeMem = runtime.freeMemory()
            val usedMem = totalMem - freeMem
            append("JVM Heap Max     : ").append(formatBytes(maxMem)).append("\n")
            append("JVM Heap Total   : ").append(formatBytes(totalMem)).append("\n")
            append("JVM Heap Used    : ").append(formatBytes(usedMem)).append("\n")
            append("JVM Heap Free    : ").append(formatBytes(freeMem)).append("\n")

            // System Memory
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            if (am != null) {
                am.getMemoryInfo(memInfo)
                append("Sys Mem Total    : ").append(formatBytes(memInfo.totalMem)).append("\n")
                append("Sys Mem Avail    : ").append(formatBytes(memInfo.availMem)).append("\n")
                append("Sys Mem Threshold: ").append(formatBytes(memInfo.threshold)).append("\n")
                append("Sys Low Memory   : ").append(memInfo.lowMemory).append("\n")
            }

            // Storage
            val filesDir = context.filesDir
            append("Internal Storage : Free ")
                .append(formatBytes(filesDir.usableSpace))
                .append(" / Total ")
                .append(formatBytes(filesDir.totalSpace))
                .append("\n")

            // Battery
            runCatching {
                val batteryFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                val batteryIntent = context.registerReceiver(null, batteryFilter)
                if (batteryIntent != null) {
                    val level = batteryIntent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
                    val scale = batteryIntent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
                    val pct = if (level >= 0 && scale > 0) (level * 100) / scale else -1
                    val status = batteryIntent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
                    val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                            status == BatteryManager.BATTERY_STATUS_FULL
                    val plugged = batteryIntent.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1)
                    val plugType = when (plugged) {
                        BatteryManager.BATTERY_PLUGGED_AC -> "AC"
                        BatteryManager.BATTERY_PLUGGED_USB -> "USB"
                        BatteryManager.BATTERY_PLUGGED_WIRELESS -> "Wireless"
                        else -> "Unplugged"
                    }
                    append("Battery Level    : ").append(if (pct >= 0) "$pct%" else "Unknown")
                        .append(" (Charging: ").append(isCharging).append(", Plug: ").append(plugType).append(")\n")
                }
            }

            // Power save mode
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            append("Power Save Mode  : ").append(pm?.isPowerSaveMode ?: false).append("\n")

            // Network
            runCatching {
                val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                val activeNetwork = cm?.activeNetwork
                val caps = cm?.getNetworkCapabilities(activeNetwork)
                if (caps != null) {
                    val types = mutableListOf<String>()
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) types.add("WiFi")
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) types.add("Cellular")
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) types.add("Ethernet")
                    if (caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) types.add("VPN")
                    val validated = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)
                    append("Network Transport: ").append(if (types.isEmpty()) "Unknown" else types.joinToString(", "))
                        .append(" (Validated: ").append(validated).append(")\n")
                } else {
                    append("Network Transport: Disconnected / Unavailable\n")
                }
            }
        }

        // 4. Crashing Thread
        appendSection(sb, "CRASHING THREAD") {
            append("ID               : ").append(thread.id).append("\n")
            append("Name             : ").append(thread.name).append("\n")
            append("Priority         : ").append(thread.priority).append("\n")
            append("State            : ").append(thread.state).append("\n")
            append("Daemon           : ").append(thread.isDaemon).append("\n")
            append("Thread Group     : ").append(thread.threadGroup?.name ?: "(None)").append("\n")
            append("Interrupted      : ").append(thread.isInterrupted).append("\n")
        }

        // 5. Exception & Stack Trace
        appendSection(sb, "EXCEPTION DETAILS & STACK TRACE") {
            append("Exception Class  : ").append(throwable.javaClass.name).append("\n")
            append("Message          : ").append(throwable.message ?: "(null)").append("\n")
            append("Localized Message: ").append(throwable.localizedMessage ?: "(null)").append("\n\n")

            append("Full Stack Trace:\n")
            append(throwable.stackTraceToString().trimEnd()).append("\n\n")

            val causes = getCauseChain(throwable)
            if (causes.size > 1) {
                append("Root Cause Chain:\n")
                causes.forEachIndexed { index, cause ->
                    append("  [").append(index).append("] ")
                        .append(cause.javaClass.name)
                        .append(": ")
                        .append(cause.message ?: "")
                        .append("\n")
                }
            }
        }

        // 6. All Active Threads Dump
        appendSection(sb, "ALL LIVE THREADS DUMP") {
            val allTraces = Thread.getAllStackTraces()
            append("Total Active Threads: ").append(allTraces.size).append("\n\n")
            for ((t, stack) in allTraces) {
                val isCrashing = t.id == thread.id
                append("Thread #").append(t.id).append(" \"").append(t.name).append("\"")
                if (isCrashing) append(" [CRASHING THREAD]")
                append("\n  State: ").append(t.state)
                    .append(", Priority: ").append(t.priority)
                    .append(", Daemon: ").append(t.isDaemon)
                    .append(", Group: ").append(t.threadGroup?.name ?: "None")
                    .append("\n")
                if (stack.isEmpty()) {
                    append("  (No stack trace)\n")
                } else {
                    for (element in stack) {
                        append("    at ").append(element.toString()).append("\n")
                    }
                }
                append("\n")
            }
        }

        // 7. Crash Breadcrumbs
        appendSection(sb, "CRASH BREADCRUMBS (RECENT EVENTS)") {
            append(CrashBreadcrumbs.formatAll()).append("\n")
        }

        // 8. Recent Logcat
        appendSection(sb, "RECENT LOGCAT (LAST 150 LINES)") {
            val logcat = captureLogcat()
            append(logcat).append("\n")
        }

        sb.append("================================================================================\n")
        sb.append("                             END OF REPORT\n")
        sb.append("================================================================================\n")

        return sb.toString()
    }

    private inline fun appendSection(sb: StringBuilder, title: String, block: StringBuilder.() -> Unit) {
        sb.append("--------------------------------------------------------------------------------\n")
        sb.append("  ").append(title).append("\n")
        sb.append("--------------------------------------------------------------------------------\n")
        sb.block()
        sb.append("\n")
    }

    private fun getCauseChain(throwable: Throwable): List<Throwable> {
        val list = mutableListOf<Throwable>()
        var current: Throwable? = throwable
        while (current != null && !list.contains(current)) {
            list.add(current)
            current = current.cause
        }
        return list
    }

    private fun getProcessName(context: Context): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            android.app.Application.getProcessName()
        } else {
            runCatching {
                val pid = Process.myPid()
                val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                am?.runningAppProcesses?.firstOrNull { it.pid == pid }?.processName
            }.getOrNull() ?: context.packageName
        }
    }

    private fun formatDuration(millis: Long): String {
        val seconds = (millis / 1000) % 60
        val minutes = (millis / (1000 * 60)) % 60
        val hours = (millis / (1000 * 60 * 60))
        return String.format(Locale.US, "%02d:%02d:%02d (%d ms)", hours, minutes, seconds, millis)
    }

    private fun formatBytes(bytes: Long): String {
        if (bytes <= 0) return "0 B"
        val mb = bytes.toDouble() / (1024 * 1024)
        return if (mb >= 1024) {
            String.format(Locale.US, "%.2f GB (%d bytes)", mb / 1024, bytes)
        } else {
            String.format(Locale.US, "%.2f MB (%d bytes)", mb, bytes)
        }
    }

    private fun captureLogcat(): String {
        return runCatching {
            val process = Runtime.getRuntime().exec(
                arrayOf("logcat", "-d", "-v", "time", "-t", "150")
            )
            // Wait up to 1 second
            val finished = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                process.waitFor(1000, TimeUnit.MILLISECONDS)
            } else {
                true
            }
            if (!finished) {
                process.destroy()
                return@runCatching "(Logcat read timed out)"
            }
            BufferedReader(InputStreamReader(process.inputStream)).use { reader ->
                val lines = reader.readLines()
                if (lines.isEmpty()) "(No logcat output)" else lines.joinToString("\n")
            }
        }.getOrElse { e ->
            "(Failed to capture logcat: ${e.message})"
        }
    }
}
