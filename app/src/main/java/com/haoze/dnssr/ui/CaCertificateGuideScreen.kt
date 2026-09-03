package com.haoze.dnssr.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.haoze.dnssr.ui.components.SettingsScaffold

private val caCertificateGuideMarkdown = """
Android（安卓）系统中，安装和卸载CA证书（通常用于网络调试、公司内网访问或特定安全软件）的步骤因系统版本和手机厂商（如华为、小米、OPPO、VIVO等）的定制界面而略有不同，但核心逻辑是一致的。

以下是通用的操作指南：

---

## 一、 如何安装 CA 证书

### 前提条件

在开始之前，请确保你已经将证书文件（通常是 `.crt`、`.cer` 或 `.der` 格式）下载到了手机的本地存储（如“下载”/`Download` 文件夹）中。

### 详细步骤

1. 打开手机的 **设置 (Settings)**。
2. 找到并点击 **安全** 或 **隐私与安全**（部分机型在 **更多设置** -> **系统安全** 中）。
3. 往下滚动，找到 **更多安全设置** 或 **凭据存储**。
4. 点击 **从存储设备安装证书**（或者 **安装证书**）。
5. 在弹出的选项中，选择 **CA 证书**。
> ⚠️ **注意：** 此时系统通常会弹出一条警告，提示“您的隐私可能受到监视”，请确认证书来源安全，然后点击 **仍然安装**。

6. 验证你的手机锁屏密码（指纹、面容或图案）。
7. 系统会打开文件管理器，找到并点击你事先下载好的证书文件。
8. 为证书命名（可以自定义，方便以后识别），用途一般保持默认的“VPN 和应用”，点击确定即可。

---

## 二、 如何卸载/删除 CA 证书

如果你不再需要某个 CA 证书，或者为了安全起见想要移除它，可以按照以下步骤操作：

### 详细步骤

1. 打开手机的 **设置 (Settings)**。
2. 前往 **安全** -> **更多安全设置** -> **凭据存储**（路径与安装时相同）。
3. 点击 **信任的凭据**（或 **查看安全凭据**）。
4. 在这里你会看到两个标签页：
* **系统：** 手机出厂自带的官方证书（**切勿随意修改或删除**）。
* **用户：** 你自己安装的所有第三方证书。

5. 切换到 **用户 (User)** 标签页。
6. 找到你想要删除的证书，点击它。
7. 滚动到页面底部，点击 **删除** 或 **移除**。
8. 确认删除后，该证书就会从系统中彻底清除。

---

> **安全提示：** CA 证书拥有极高的权限，可以截获和解析你手机上发出的加密网络流量（HTTPS）。请**务必不要**安装任何来自未知来源、陌生网页或不可信应用提示安装的 CA 证书。
""".trimIndent()

private val caCertificateGuideMarkdownEnglish = """
The steps for installing and removing a CA certificate on Android vary slightly by system version and device manufacturer, but the core process is the same.

The following is a general guide:

---

## I. Installing a CA certificate

### Before you begin

Make sure the certificate file, usually in `.crt`, `.cer`, or `.der` format, has been downloaded to local storage, such as the `Download` folder.

### Steps

1. Open the phone's **Settings**.
2. Open **Security** or **Privacy and security**. Some devices place it under **More settings** -> **System security**.
3. Open **More security settings** or **Credential storage**.
4. Tap **Install a certificate from storage** or **Install certificate**.
5. Select **CA certificate**.
> ⚠️ **Note:** Android may warn that your privacy could be monitored. Confirm that the certificate source is trusted, then tap **Install anyway**.

6. Verify the screen-lock password, fingerprint, face, or pattern.
7. Use the file picker to select the downloaded certificate.
8. Give the certificate a recognizable name. Keep the purpose as **VPN and apps** unless you have a specific reason to change it, then confirm.

---

## II. Removing a CA certificate

If a certificate is no longer needed, remove it as follows:

### Steps

1. Open the phone's **Settings**.
2. Go to **Security** -> **More security settings** -> **Credential storage**.
3. Tap **Trusted credentials** or **View security credentials**.
4. You will see two tabs:
* **System:** official certificates included by the manufacturer. **Do not modify or remove these casually.**
* **User:** third-party certificates installed by you.

5. Open the **User** tab.
6. Select the certificate to remove.
7. Scroll down and tap **Delete** or **Remove**.
8. Confirm the removal.

---

> **Security notice:** CA certificates have extensive privileges and can intercept and decrypt encrypted network traffic, including HTTPS. **Never install** a CA certificate from an unknown source, unfamiliar website, or untrusted app prompt.
""".trimIndent()

@Composable
fun CaCertificateGuideScreen(onBack: () -> Unit) {
    SettingsScaffold(title = localizedText("CA 证书安装与卸载指南"), onBack = onBack) { innerPadding ->
        val markdown = if (androidx.compose.ui.platform.LocalConfiguration.current.locales[0].language == "en") {
            caCertificateGuideMarkdownEnglish
        } else {
            caCertificateGuideMarkdown
        }
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp)
        ) {
            markdown.lines().filter(String::isNotBlank).forEach { line ->
                MarkdownLine(line)
            }
        }
    }
}

@Composable
private fun MarkdownLine(line: String) {
    val trimmed = line.trim()
    when {
        trimmed == "---" -> HorizontalDivider(modifier = Modifier.padding(vertical = 10.dp))
        trimmed.startsWith("## ") -> Text(
            inlineMarkdown(trimmed.removePrefix("## ")),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(top = 8.dp, bottom = 10.dp)
        )
        trimmed.startsWith("### ") -> Text(
            inlineMarkdown(trimmed.removePrefix("### ")),
            style = MaterialTheme.typography.titleMedium,
            modifier = Modifier.padding(top = 8.dp, bottom = 6.dp)
        )
        trimmed.startsWith("> ") -> Text(
            inlineMarkdown(trimmed.removePrefix("> ")),
            color = MaterialTheme.colorScheme.error,
            style = MaterialTheme.typography.bodyMedium.copy(lineHeight = 22.sp),
            modifier = Modifier.padding(start = 12.dp, top = 4.dp, bottom = 8.dp)
        )
        trimmed.matches(Regex("\\d+\\. .*")) -> Text(
            inlineMarkdown(trimmed),
            style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 24.sp),
            modifier = Modifier.padding(start = 4.dp, bottom = 4.dp)
        )
        trimmed.startsWith("* ") -> Text(
            inlineMarkdown("• " + trimmed.removePrefix("* ")),
            style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 24.sp),
            modifier = Modifier.padding(start = 20.dp, bottom = 4.dp)
        )
        else -> Text(
            inlineMarkdown(trimmed),
            style = MaterialTheme.typography.bodyLarge.copy(lineHeight = 24.sp),
            modifier = Modifier.padding(bottom = 8.dp)
        )
    }
}

private fun inlineMarkdown(source: String): AnnotatedString = buildAnnotatedString {
    val token = Regex("(\\*\\*.*?\\*\\*|`.*?`)")
    var cursor = 0
    token.findAll(source).forEach { match ->
        append(source.substring(cursor, match.range.first))
        val value = match.value
        if (value.startsWith("**")) {
            pushStyle(SpanStyle(fontWeight = FontWeight.Bold))
            append(value.removeSurrounding("**"))
        } else {
            pushStyle(SpanStyle(fontFamily = FontFamily.Monospace))
            append(value.removeSurrounding("`"))
        }
        pop()
        cursor = match.range.last + 1
    }
    append(source.substring(cursor))
}
