package com.haoze.dnssr.update

import android.content.Context
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.FileProvider
import com.haoze.dnssr.BuildConfig
import com.haoze.dnssr.ui.AppSettings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

data class AppUpdateInfo(
    val version: String,
    val downloadUrl: String,
    val fileName: String,
    val releaseNotes: String,
)

enum class AppUpdateDownloadStatus {
    Idle,
    Downloading,
    Downloaded,
    Failed,
}

data class AppUpdateDownloadState(
    val version: String = "",
    val localPath: String = "",
    val status: AppUpdateDownloadStatus = AppUpdateDownloadStatus.Idle,
    val downloadedBytes: Long = 0L,
    val totalBytes: Long = -1L,
)

data class AppUpdateUiState(
    val checking: Boolean = false,
    val availableUpdate: AppUpdateInfo? = null,
    val downloadState: AppUpdateDownloadState = AppUpdateDownloadState(),
    val message: String = "",
    val error: String = "",
)

class AppUpdateManager(
    private val context: Context,
    httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .callTimeout(2, TimeUnit.MINUTES)
        .build(),
) {
    private val httpClient = httpClient.newBuilder()
        .callTimeout(2, TimeUnit.MINUTES)
        .build()
    private val updateDirectory = File(context.filesDir, UPDATE_DIRECTORY)

    suspend fun checkForUpdate(): AppUpdateInfo? = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url(RELEASE_URL)
            .header("Accept", "application/vnd.github+json")
            .header("User-Agent", "DNSSR-Android")
            .build()
        httpClient.newCall(request).execute().use { response ->
            if (!response.isSuccessful) error("检查更新失败：GitHub 返回 ${response.code}")
            parseLatestRelease(response.body?.string().orEmpty(), BuildConfig.VERSION_NAME)
        }
    }

    suspend fun download(
        update: AppUpdateInfo,
        onProgress: (downloadedBytes: Long, totalBytes: Long) -> Unit,
    ): AppUpdateDownloadState = withContext(Dispatchers.IO) {
        val existing = refreshDownloadState(update)
        if (existing.status == AppUpdateDownloadStatus.Downloading || existing.status == AppUpdateDownloadStatus.Downloaded) {
            return@withContext existing
        }
        updateDirectory.mkdirs()
        val finalFile = File(updateDirectory, "update-${update.version}.apk")
        val temporaryFile = File(updateDirectory, ".update-${update.version}.apk.part")
        finalFile.delete()
        temporaryFile.delete()
        try {
            if (!isAllowedDownloadUrl(update.downloadUrl)) {
                error("更新地址不受信任")
            }
            val request = Request.Builder()
                .url(update.downloadUrl)
                .header("User-Agent", "DNSSR-Android")
                .build()
            val downloadState = httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) error("下载更新失败：服务器返回 ${response.code}")
                val body = response.body ?: error("下载更新失败：响应内容为空")
                val totalBytes = body.contentLength().takeIf { it > 0L } ?: -1L
                if (totalBytes > MAX_APK_BYTES) {
                    error("更新包超过大小限制")
                }
                var downloadedBytes = 0L
                var lastReportedBytes = -1L
                fun reportProgress(force: Boolean = false) {
                    if (force || downloadedBytes - lastReportedBytes >= PROGRESS_UPDATE_BYTES) {
                        onProgress(downloadedBytes, totalBytes)
                        lastReportedBytes = downloadedBytes
                    }
                }
                reportProgress(force = true)
                body.byteStream().use { input ->
                    temporaryFile.outputStream().buffered().use { output ->
                        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                        while (true) {
                            currentCoroutineContext().ensureActive()
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                            downloadedBytes += read
                            if (downloadedBytes > MAX_APK_BYTES) {
                                error("更新包超过大小限制")
                            }
                            reportProgress()
                        }
                    }
                }
                reportProgress(force = true)
                if (!temporaryFile.renameTo(finalFile)) error("下载更新失败：无法保存安装包")
                if (!isValidDownloadedApk(finalFile, update.version)) {
                    finalFile.delete()
                    error("更新包校验失败")
                }
                AppSettings.rememberAppUpdateDownload(context, finalFile.absolutePath, update.version)
                AppUpdateDownloadState(
                    version = update.version,
                    localPath = finalFile.absolutePath,
                    status = AppUpdateDownloadStatus.Downloaded,
                    downloadedBytes = downloadedBytes,
                    totalBytes = totalBytes,
                )
            }
            downloadState
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            temporaryFile.delete()
            throw cancelled
        } catch (_: Throwable) {
            temporaryFile.delete()
            finalFile.delete()
            AppSettings.clearAppUpdateDownload(context)
            AppUpdateDownloadState(version = update.version, status = AppUpdateDownloadStatus.Failed)
        }
    }

    suspend fun refreshDownloadState(update: AppUpdateInfo): AppUpdateDownloadState = withContext(Dispatchers.IO) {
        val localPath = AppSettings.getAppUpdateDownloadPath(context)
        if (localPath.isBlank() || AppSettings.getAppUpdateDownloadVersion(context) != update.version) {
            return@withContext AppUpdateDownloadState(version = update.version)
        }
        val localFile = File(localPath)
        if (!isValidDownloadedApk(localFile, update.version)) {
            AppSettings.clearAppUpdateDownload(context)
            return@withContext AppUpdateDownloadState(version = update.version)
        }
        AppUpdateDownloadState(
            version = update.version,
            localPath = localPath,
            status = AppUpdateDownloadStatus.Downloaded,
            downloadedBytes = localFile.length(),
            totalBytes = localFile.length(),
        )
    }

    fun installDownloadedUpdate(update: AppUpdateInfo): Boolean {
        return runCatching {
            val path = AppSettings.getAppUpdateDownloadPath(context)
            check(path.isNotBlank() && AppSettings.getAppUpdateDownloadVersion(context) == update.version)
            val apkFile = File(path)
            check(isValidDownloadedApk(apkFile, update.version))
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apkFile)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
        }.isSuccess
    }

    private fun isAllowedDownloadUrl(value: String): Boolean {
        val url = value.toHttpUrlOrNull() ?: return false
        return url.scheme == "https" && url.host == "github.com"
    }

    private fun isValidDownloadedApk(file: File, expectedVersion: String): Boolean {
        if (!file.isFile || file.length() <= 0L || file.length() > MAX_APK_BYTES) return false
        val packageManager = context.packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }
        val installed = runCatching {
            packageManager.getPackageInfo(context.packageName, flags)
        }.getOrNull() ?: return false
        val archive = packageManager.getPackageArchiveInfo(file.absolutePath, flags) ?: return false
        if (archive.packageName != context.packageName || !sameVersion(archive.versionName, expectedVersion)) {
            return false
        }
        val installedCertificates = signingCertificates(installed)
        val archiveCertificates = signingCertificates(archive)
        return installedCertificates.isNotEmpty() &&
            installedCertificates.size == archiveCertificates.size &&
            archiveCertificates.all { archiveCertificate ->
                installedCertificates.any { installedCertificate ->
                    archiveCertificate.contentEquals(installedCertificate)
                }
            }
    }

    private fun signingCertificates(packageInfo: PackageInfo): List<ByteArray> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return packageInfo.signingInfo?.apkContentsSigners
                ?.map { it.toByteArray() }
                .orEmpty()
        }
        @Suppress("DEPRECATION")
        return packageInfo.signatures?.map { it.toByteArray() }.orEmpty()
    }

    private companion object {
        const val UPDATE_DIRECTORY = "app-update"
        const val RELEASE_URL = "https://api.github.com/repos/haoze-evolluling/DITING/releases/latest"
        const val PROGRESS_UPDATE_BYTES = 256L * 1024L
        const val MAX_APK_BYTES = 100L * 1024L * 1024L
    }
}

internal fun parseLatestRelease(payload: String, currentVersion: String): AppUpdateInfo? {
    val release = JSONObject(payload)
    val remoteVersion = release.optString("tag_name").trim()
    if (!isNewerVersion(remoteVersion, currentVersion)) return null
    val assets = release.optJSONArray("assets") ?: JSONArray()
    val asset = (0 until assets.length())
        .mapNotNull { index -> assets.optJSONObject(index) }
        .firstOrNull { it.optString("name").endsWith(".apk", ignoreCase = true) && it.optString("name").contains("arm64-v8a", ignoreCase = true) }
        ?: (0 until assets.length())
            .mapNotNull { index -> assets.optJSONObject(index) }
            .firstOrNull { it.optString("name").endsWith(".apk", ignoreCase = true) }
        ?: error("最新版本未提供 Android APK")
    val downloadUrl = asset.optString("browser_download_url").trim()
    if (downloadUrl.isBlank()) error("更新包下载地址无效")
    return AppUpdateInfo(
        version = remoteVersion.removePrefix("v"),
        downloadUrl = downloadUrl,
        fileName = asset.optString("name").ifBlank { "谛听-$remoteVersion.apk" },
        releaseNotes = release.optString("body").trim(),
    )
}

internal fun isNewerVersion(remote: String, current: String): Boolean {
    val remoteParts = parseVersionComponents(remote) ?: return false
    val currentParts = parseVersionComponents(current) ?: return false
    val length = maxOf(remoteParts.size, currentParts.size)
    repeat(length) { index ->
        val difference = remoteParts.getOrElse(index) { 0 }.compareTo(currentParts.getOrElse(index) { 0 })
        if (difference != 0) return difference > 0
    }
    return false
}

private fun sameVersion(left: String?, right: String): Boolean {
    val leftParts = parseVersionComponents(left.orEmpty()) ?: return false
    val rightParts = parseVersionComponents(right) ?: return false
    val length = maxOf(leftParts.size, rightParts.size)
    return (0 until length).all { index ->
        leftParts.getOrElse(index) { 0 } == rightParts.getOrElse(index) { 0 }
    }
}

private fun parseVersionComponents(value: String): List<Int>? {
    val normalized = value.trim().removePrefix("v").substringBefore('-')
    if (normalized.isBlank()) return null
    return normalized.split('.').map { part -> part.toIntOrNull() ?: return null }
}

