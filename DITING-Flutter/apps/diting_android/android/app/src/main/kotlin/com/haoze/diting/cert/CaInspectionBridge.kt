package com.haoze.diting.cert

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.security.KeyChain
import android.provider.Settings
import androidx.core.content.FileProvider
import com.haoze.diting.platform.ChannelResults
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.security.cert.CertificateFactory
import java.security.cert.X509Certificate
import java.util.concurrent.Executors
import tunnel.Engine

/// The MITM root CA; `installed` = SHA-256 match in the `user:` store, the only writable one.
class CaInspectionBridge(private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.haoze.diting/https_inspection"

        const val EXPORTED_CERTIFICATE_NAME = "谛听-HTTPS-Inspection-Root-CA.crt"

        /// Engine() is too slow for the platform thread; a failed dlopen must surface
        private val worker = Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "diting-ca").apply { isDaemon = true }
        }

        private const val MITM_DIR = "go-mitm"
        private const val CA_CERT_FILE = "ca.crt"
        private const val CA_KEY_FILE = "ca.key"
        private const val MITM_BLACKLIST_FILE = "mitm_blacklist.txt"

        /// Staging area for the installer hand-off; declared in `res/xml/file_paths.xml`
        private const val EXPORT_DIR = "ca-export"

        /// Shown by the system installer; distinctive so the user can tell it from other CAs
        private const val CA_DISPLAY_NAME = "谛听 HTTPS 检查根证书"
    }

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "inspectCa" -> {
                val regenerate = call.argument<Boolean>("regenerate") ?: false
                worker.execute {
                    val value = runCatching { inspect(regenerate) }
                    ChannelResults.ship(result, value, "ca_inspect_failed")
                }
            }
            "exportCa" -> {
                val uri = call.argument<String>("uri").orEmpty()
                worker.execute {
                    val value = runCatching { export(Uri.parse(uri)) }
                    ChannelResults.ship(result, value, "ca_export_failed")
                }
            }
            // File system + intent work: never on the platform thread for the write, and the
            // installer must be launched from a thread it can see the grant from.
            "installCa" -> worker.execute {
                val value = runCatching { installCertificate() }
                ChannelResults.ship(result, value, "ca_install_failed")
            }
            "saveCa" -> worker.execute {
                val value = runCatching { saveToDownloads() }
                ChannelResults.ship(result, value, "ca_save_failed")
            }
            else -> result.notImplemented()
        }
    }

    private fun inspect(regenerate: Boolean): Map<String, Any?> {
        if (regenerate) reset()

        // Reading the cached `ca.crt` avoids spawning the Go engine on every page open: the
        // engine exists to mint the pair, not to serve it back. Only a missing file pays the
        // cost (and only then can an ABI mismatch surface).
        val cached = if (regenerate) null else readCachedPem()
        val outcome = if (cached != null) Success(cached) else generate()
        if (outcome is Failure) {
            return mapOf(
                "available" to false,
                "installed" to false,
                "fingerprintSha256" to null,
                "pem" to null,
                "error" to outcome.message,
            )
        }
        val text = (outcome as Success).value
        if (text.isEmpty()) {
            return mapOf(
                "available" to false,
                "installed" to false,
                "fingerprintSha256" to null,
                "pem" to null,
                "error" to "证书引擎未返回根证书",
            )
        }

        val fingerprint = runCatching { fingerprintOfPem(text) }.getOrNull()
        return mapOf(
            "available" to true,
            "installed" to (fingerprint != null && isInstalled(fingerprint)),
            "fingerprintSha256" to fingerprint,
            "pem" to text,
            // Present but unparsable: something this device's CertificateFactory rejects.
            "error" to if (fingerprint == null) "根证书无法解析" else null,
        )
    }

    /// Hands the PEM to the system certificate installer through a `content://` URI. Without
    /// this the only thing the app could do was open the security settings screen, which is why
    /// "install" never actually installed anything.
    private fun installCertificate(): Map<String, Any?> {
        val pem = currentPem()
            ?: return installResult("none", null, "还没有可用证书，请先重新生成根证书")

        val file = File(context.cacheDir, EXPORT_DIR).apply { mkdirs() }
            .resolve(EXPORTED_CERTIFICATE_NAME)
        runCatching { file.writeText(pem, Charsets.UTF_8) }
            .onFailure { return installResult("none", null, describe(it)) }

        // KeyChain.createInstallIntent() is the only hand-off the platform installer accepts for
        // a CA: ACTION_VIEW on the file merely opens CertInstaller's "install this from Settings"
        // notice, which has a single Close button and installs nothing.
        val bundleInstaller = runCatching {
            val intent = KeyChain.createInstallIntent().apply {
                putExtra(KeyChain.EXTRA_CERTIFICATE, pem.toByteArray(Charsets.UTF_8))
                putExtra(KeyChain.EXTRA_NAME, CA_DISPLAY_NAME)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
        if (bundleInstaller.isSuccess) {
            return installResult("installer", file.absolutePath, null)
        }

        // Older ROMs only understand the file-based ACTION_VIEW hand-off.
        val launchInstaller = runCatching {
            val uri: Uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                file,
            )
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/x-x509-ca-cert")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
        if (launchInstaller.isSuccess) {
            return installResult("installer", file.absolutePath, null)
        }

        // No installer activity (rare, some OEM roms strip it): the file is staged, so send the
        // user to the manual entry point and say so instead of pretending it installed.
        val settings = runCatching {
            context.startActivity(
                Intent(Settings.ACTION_SECURITY_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            )
        }
        return if (settings.isSuccess) {
            installResult("settings", file.absolutePath, null)
        } else {
            installResult("none", file.absolutePath, "系统没有可用的证书安装界面")
        }
    }

    private fun installResult(mode: String, path: String?, error: String?): Map<String, Any?> =
        mapOf("mode" to mode, "path" to path, "error" to error)

    /// Copies the PEM into the shared Download folder so it can be installed later from a file
    /// manager, or fetched over USB. MediaStore needs no storage permission on Android 10+.
    private fun saveToDownloads(): Map<String, Any?> {
        val pem = currentPem()
            ?: return saveResult(false, null, "还没有可用证书，请先重新生成根证书")
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return saveToPrivateDownloads(pem)
        }
        return runCatching {
            val resolver = context.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, EXPORTED_CERTIFICATE_NAME)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/x-x509-ca-cert")
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return saveResult(false, null, "无法在下载目录创建文件")
            val stream = resolver.openOutputStream(uri)
                ?: return saveResult(false, null, "无法写入下载目录")
            stream.use { it.write(pem.toByteArray(Charsets.UTF_8)) }
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            saveResult(true, "Download/$EXPORTED_CERTIFICATE_NAME", null)
        }.getOrElse { saveToPrivateDownloads(pem) }
    }

    /// Fallback for API < 29 and MediaStore failures: app-private Downloads, no permission needed.
    private fun saveToPrivateDownloads(pem: String): Map<String, Any?> = runCatching {
        val root = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: File(context.filesDir, "downloads")
        if (!root.exists()) root.mkdirs()
        val file = File(root, EXPORTED_CERTIFICATE_NAME)
        file.writeText(pem, Charsets.UTF_8)
        saveResult(true, file.absolutePath, null)
    }.getOrElse { saveResult(false, null, describe(it)) }

    private fun saveResult(saved: Boolean, name: String?, error: String?): Map<String, Any?> =
        mapOf("saved" to saved, "name" to name, "error" to error)

    private fun export(uri: Uri) {
        val pem = currentPem() ?: error("证书引擎未返回根证书")
        val stream = context.contentResolver.openOutputStream(uri, "w")
            ?: error("无法写入所选位置")
        stream.use { it.write(pem.toByteArray(Charsets.UTF_8)) }
    }

    /// Cached PEM first; the engine is the generator of record, not a read path.
    private fun currentPem(): String? = readCachedPem() ?: when (val result = generate()) {
        is Success -> result.value
        is Failure -> null
    }

    private fun readCachedPem(): String? = runCatching {
        File(certificateDirectory(), CA_CERT_FILE)
            .takeIf { it.isFile }
            ?.readText(Charsets.UTF_8)
            ?.takeIf { it.isNotBlank() }
    }.getOrNull()

    /// Asks the Go engine to mint the pair (it writes `ca.crt` into the mitm directory).
    private fun generate(): Outcome = runCatching {
        // Engine() must be stopped: its DNS cache cleaner goroutine only exits via stop().
        val engine = Engine()
        try {
            engine.startStackMitm(certificateDirectory().absolutePath)
        } finally {
            runCatching { engine.stopStackMitm() }
            runCatching { engine.stop() }
        }
    }.fold(
        onSuccess = { Success(it) },
        // ABI mismatch (arm64-only libgojni.so on x86_64) shows up here and must be reported.
        onFailure = { Failure(describe(it)) },
    )

    private fun reset() {
        certificateDirectory().listFiles()?.forEach { file ->
            if (file.name == CA_CERT_FILE ||
                file.name == CA_KEY_FILE ||
                file.name == MITM_BLACKLIST_FILE
            ) {
                runCatching { file.delete() }
            }
        }
    }

    private fun certificateDirectory(): File =
        File(context.filesDir, MITM_DIR).apply { mkdirs() }

    private fun isInstalled(fingerprint: String): Boolean = runCatching {
        val store = KeyStore.getInstance("AndroidCAStore").apply { load(null) }
        store.aliases().asSequence()
            .filter { it.startsWith("user:") }
            .mapNotNull { store.getCertificate(it) as? X509Certificate }
            .any { certificate -> fingerprintOfBytes(certificate.encoded) == fingerprint }
    }.getOrDefault(false)

    private fun fingerprintOfPem(pem: String): String {
        val certificate = CertificateFactory.getInstance("X.509")
            .generateCertificate(pem.byteInputStream()) as X509Certificate
        return fingerprintOfBytes(certificate.encoded)
    }

    /// Colon-separated uppercase hex, as displayed verbatim
    private fun fingerprintOfBytes(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256")
            .digest(bytes)
            .joinToString(":") { "%02X".format(it) }

    private fun describe(error: Throwable): String {
        val message = error.message.orEmpty()
        // UnsatisfiedLinkError's message is the only real diagnostic, so pass it through.
        return when {
            error is UnsatisfiedLinkError -> "证书引擎加载失败：$message"
            message.isEmpty() -> error.javaClass.simpleName
            else -> message
        }
    }

    /// Tiny sealed result so `inspect()` can tell "engine failed" from "engine gave nothing".
    private sealed interface Outcome {
        val message: String
    }

    private class Success(val value: String) : Outcome {
        override val message: String get() = value
    }

    private class Failure(override val message: String) : Outcome
}
